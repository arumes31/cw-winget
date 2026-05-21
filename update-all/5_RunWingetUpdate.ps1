# 5_RunWingetUpdate.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result|WingetLog

$State = @'
@state@
'@.Trim()

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()
$Password = $Parts[2].Trim()

# Elevation check for setup
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Elevating setup process..."
}

$TaskName = "TempWingetTask_$(Get-Random)"
$WorkDir = "C:\eworx"
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

# Explicitly grant Edit permission to localized Administrators group (S-1-5-32-544)
# to ensure Start-Transcript and File operations work within the Scheduled Task
try {
    # Robust localized Administrators group lookup
    $AdminGroup = (Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction SilentlyContinue).Name
    if (-not $AdminGroup) {
        $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $Translated = $AdminSid.Translate([System.Security.Principal.NTAccount]).Value
        $AdminGroup = $Translated.Split('\')[-1]
    }
    
    $Acl = Get-Acl $WorkDir
    $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($AdminGroup, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $Acl.AddAccessRule($Ar)
    Set-Acl $WorkDir $Acl
}
catch {
    Write-Host "Warning: Failed to set ACL on $($WorkDir): $($_.Exception.Message)"
}

$LogPath = Join-Path -Path $WorkDir -ChildPath "winget-log.txt"
$TempScriptPath = Join-Path -Path $WorkDir -ChildPath "TempWingetUpdate_$(Get-Random).ps1"

if (Test-Path $LogPath) { Remove-Item $LogPath -Force }

$UpdateScriptContent = @"
# Force profile loading variables if they are missing
if (-not `$env:LOCALAPPDATA) { `$env:LOCALAPPDATA = "`$env:USERPROFILE\AppData\Local" }

Start-Transcript -Path '$LogPath' -Append
try {
    # 1. Proactively stop any hung msiexec processes to clear installer database locks
    try {
        Stop-Process -Name msiexec -Force -ErrorAction SilentlyContinue
    } catch {}

    # 2. Enable and start Windows Installer service to prevent 1601 errors
    try {
        Set-Service -Name msiserver -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name msiserver -ErrorAction SilentlyContinue
    } catch {}

    function Test-IsAdmin {
        `$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        `$principal = New-Object Security.Principal.WindowsPrincipal(`$currentUser)
        return `$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    # Helper to execute WinGet with a strict 10-minute timeout per package to prevent background hangs
    function Invoke-WingetCommand {
        param(
            [string]`$Arguments
        )
        
        Write-Output "DEBUG: Running process: `$WingetCmd `$Arguments"
        
        try {
            `$Proc = Start-Process -FilePath `$WingetCmd -ArgumentList `$Arguments -NoNewWindow -PassThru
            
            `$TimeoutSeconds = 600 # 10 minutes
            `$Slept = 0
            while (-not `$Proc.HasExited -and `$Slept -lt `$TimeoutSeconds) {
                Start-Sleep -Seconds 5
                `$Slept += 5
            }
            
            if (-not `$Proc.HasExited) {
                Write-Warning "Process timed out after `$TimeoutSeconds seconds. Terminating process and child installers."
                try {
                    Stop-Process -Id `$Proc.Id -Force -ErrorAction SilentlyContinue
                    
                    # Kill child processes spawned by this installer to clean up fully
                    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
                        Get-CimInstance Win32_Process -Filter "ParentProcessId = `$(`$Proc.Id)" -ErrorAction SilentlyContinue | ForEach-Object {
                            Stop-Process -Id `$_.ProcessId -Force -ErrorAction SilentlyContinue
                        }
                    } elseif (Get-Command Get-WmiObject -ErrorAction SilentlyContinue) {
                        Get-WmiObject Win32_Process -Filter "ParentProcessId = `$(`$Proc.Id)" -ErrorAction SilentlyContinue | ForEach-Object {
                            Stop-Process -Id `$_.ProcessId -Force -ErrorAction SilentlyContinue
                        }
                    }
                } catch {
                    Write-Output "Warning during process termination: `$(`$_.Exception.Message)"
                }
            } else {
                Write-Output "Process exited with code `$(`$Proc.ExitCode)."
            }
        } catch {
            Write-Error "Failed to invoke winget: `$(`$_.Exception.Message)"
        }
    }

    # Deep Initialization for WinGet in new user profile
    try {
        # 1. Direct Source Injection & AppInstaller Registration (CRITICAL FIRST STEP)
        # This ensures the winget executable is present and registered before discovery
        Add-AppxPackage -Path "https://cdn.winget.microsoft.com/cache/source.msix" -ErrorAction SilentlyContinue
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
        
        # 2. Module & Repair (Ensures latest client logic)
        if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client)) {
            Install-PackageProvider -Name 'NuGet' -Force -ErrorAction SilentlyContinue
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module -Name Microsoft.WinGet.Client -Force -Confirm:`$false -Scope CurrentUser -ErrorAction SilentlyContinue
        }
        
        Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
        if (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue) {
            Repair-WinGetPackageManager -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Output "Init Warning: `$(`$_.Exception.Message)"
    }

    # 3. Robust WinGet command discovery (AFTER registration)
    `$WingetCmd = "winget"
    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        `$PotentialPaths = @(
            "`$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "`$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe",
            "`$env:USERPROFILE\AppData\Local\Microsoft\WindowsApps\winget.exe"
        )
        foreach (`$Path in `$PotentialPaths) {
            `$ResolvedPath = Resolve-Path `$Path -ErrorAction SilentlyContinue
            if (`$ResolvedPath) {
                `$WingetCmd = `$ResolvedPath.Path
                Write-Output "DEBUG: Found winget at `$WingetCmd"
                break
            }
        }
    }

    # Aggressive fix for error 0x8a15000f (Source data missing)
    `$WingetAppData = Join-Path `$env:LOCALAPPDATA "Microsoft\WinGet"
    `$WingetLocalState = Join-Path `$env:LOCALAPPDATA "Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState"

    if (Test-Path `$WingetAppData) { Remove-Item -Path `$WingetAppData -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path `$WingetLocalState) { Remove-Item -Path `$WingetLocalState -Recurse -Force -ErrorAction SilentlyContinue }

    # Nuclear option: Remove sources first to ensure clean slate
    & `$WingetCmd source remove --name winget 2>&1 | Out-Null
    & `$WingetCmd source remove --name msstore 2>&1 | Out-Null

    # Re-inject source to be absolutely sure
    Add-AppxPackage -Path "https://cdn.winget.microsoft.com/cache/source.msix" -ErrorAction SilentlyContinue

    # Reset and Update
    & `$WingetCmd source reset --force
    & `$WingetCmd source update

    # Stabilization delay to ensure source index is flushed to disk
    Start-Sleep -Seconds 10

    # Debug: List sources to log
    & `$WingetCmd source list

    # Trigger index creation
    & `$WingetCmd search "NuGet" --accept-source-agreements | Out-Null

    # --- IGNORING LOGIC AND UPGRADE EXECUTION ---
    `$IgnoreFile = "C:\Windows\LTSvc\eworx\winget\ignoredprograms.txt"
    `$IgnoreList = @()
    if (Test-Path `$IgnoreFile) {
        `$IgnoreList = Get-Content `$IgnoreFile | Where-Object { `$_.Trim() -ne "" } | ForEach-Object { `$_.Trim().ToLower() }
        Write-Output "Loaded `$(`$IgnoreList.Count) ignore entries from `$IgnoreFile"
    }

    if (`$IgnoreList.Count -eq 0) {
        Write-Output "No ignore list found or list is empty. Running upgrade --all..."
        Invoke-WingetCommand "upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --scope machine --include-unknown"
    } else {
        Write-Output "Checking for available upgrades to apply exclusions..."
        `$Upgrades = & `$WingetCmd upgrade --accept-source-agreements
        
        # LANGUAGE-AGNOSTIC PARSING: Find the dashed line to identify headers and columns
        `$DashLine = `$Upgrades | Where-Object { `$_ -match "^-{10,}" } | Select-Object -First 1
        `$DashIndex = [array]::IndexOf(`$Upgrades, `$DashLine)

        if (`$DashIndex -gt 0 -and `$DashIndex -lt (`$Upgrades.Count - 1)) {
            `$HeaderLine = `$Upgrades[`$DashIndex - 1]
            `$HeaderParts = `$HeaderLine -split '\s{2,}'
            
            if (`$HeaderParts.Count -ge 3) {
                `$IdHeader = `$HeaderParts[1]
                `$VersionHeader = `$HeaderParts[2]
                
                `$IdStart = `$HeaderLine.IndexOf(`$IdHeader)
                `$VersionStart = `$HeaderLine.IndexOf(`$VersionHeader)
                `$IdLength = `$VersionStart - `$IdStart

                for (`$i = `$DashIndex + 1; `$i -lt `$Upgrades.Count; `$i++) {
                    `$Line = `$Upgrades[`$i]
                    if ([string]::IsNullOrWhiteSpace(`$Line)) { continue }
                    if (`$Line.Length -lt `$IdStart) { continue }
                    
                    `$AppName = `$Line.Substring(0, `$IdStart).Trim()
                    `$AppId = ""
                    if (`$Line.Length -ge `$VersionStart) {
                        `$AppId = `$Line.Substring(`$IdStart, `$IdLength).Trim()
                    } else {
                        `$AppId = `$Line.Substring(`$IdStart).Trim()
                    }
                    
                    # Skip summary/warning lines that might be parsed on localized systems
                    if (`$AppId.Contains(" ") -or `$AppId -match "\s") { continue }
                    
                    `$Skip = `$false
                    foreach (`$IgnoreItem in `$IgnoreList) {
                        if (`$AppName.ToLower().Contains(`$IgnoreItem) -or `$AppId.ToLower().Contains(`$IgnoreItem)) {
                            `$Skip = `$true
                            break
                        }
                    }
                    
                    if (`$Skip) {
                        Write-Output "Skipping ignored application: `$AppName (`$AppId)"
                    } elseif (`$AppId) {
                        Write-Output "Upgrading: `$AppName (`$AppId)..."
                        Invoke-WingetCommand "upgrade --id `"`$AppId`" --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --scope machine --include-unknown"
                    }
                }
            } else {
                Write-Output "Could not reliably parse column headers."
            }
        } else {
            Write-Output "No valid upgrade data rows found or no upgrades available."
        }
    }

} catch {
    Write-Error "Inner Script Failure: `$(`$_.Exception.Message)"
    exit 1
} finally {
    Stop-Transcript
}
"@

$UpdateScriptContent | Out-File -FilePath $TempScriptPath -Encoding UTF8

try {
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TempScriptPath`""
    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date)
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -User $Username -Password $Password -RunLevel Highest -Force | Out-Null
    
    Start-ScheduledTask -TaskName $TaskName
    
    $timeout = 7200 
    $startTime = Get-Date
    $taskFinished = $false
    
    do {
        Start-Sleep -Seconds 15
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task -and $task.State -ne "Running") {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
            $taskFinished = $true
            break
        }
        if (((Get-Date) - $startTime).TotalSeconds -gt $timeout) {
            Write-Warning "Task timed out. Stopping task."
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            break
        }
    } while ($true)

    $WingetLog = "No log found"
    if (Test-Path $LogPath) {
        $RawLog = Get-Content $LogPath
        $CleanLog = @()
        $InTranscriptBlock = $false
        
        # LANGUAGE-AGNOSTIC LOG CLEANUP: Drops everything between the transcript boundary boxes
        foreach ($line in $RawLog) {
            if ($line -match "^\*\*\*\*") {
                $InTranscriptBlock = -not $InTranscriptBlock
                continue
            }
            if (-not $InTranscriptBlock) {
                if ($line.Trim() -ne "" -and $line -notmatch "o{10,}" -and $line -notmatch "\[=*\]") {
                    $CleanLog += $line.Trim()
                }
            }
        }
        
        if ($CleanLog.Count -eq 0) {
            $WingetLog = "Log was empty or fully filtered."
        } else {
            $WingetLog = $CleanLog -join " ; "
        }
        
        # --- CRITICAL FIX FOR AUTOMATE STRING INJECTION ---
        # Replace newlines and carriage returns with spaces first
        $WingetLog = $WingetLog -replace "[\r\n]+", " "
        # Keep only safe, printable alphanumeric and Unicode letter characters (no single/double quotes, backticks, semicolons, or pipes)
        $WingetLog = $WingetLog -replace "[^a-zA-Z0-9\p{L}\p{N}\.\,\-\_\:\/\(\)\[\]\+\s]", ""
        # Condense multiple spaces into one
        $WingetLog = $WingetLog -replace "\s{2,}", " "
        
        if ($WingetLog.Length -gt 2000) { $WingetLog = $WingetLog.Substring(0, 2000) + "..." }
    }

    if (-not $taskFinished -or -not $taskInfo -or $taskInfo.LastTaskResult -ne 0) {
        $lastResult = if ($taskInfo) { $taskInfo.LastTaskResult } else { "Timeout" }
        Write-Error "Winget update task failed. TaskResult: $lastResult. Log: $WingetLog"
        exit 1
    }
    
    Write-Output "5|${Username}|${Password}|WingetUpdated|${WingetLog}"
}
catch {
    Write-Error "Failed to run Winget update: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    if (Test-Path $TempScriptPath) { Remove-Item -Path $TempScriptPath -Force -ErrorAction SilentlyContinue }
}