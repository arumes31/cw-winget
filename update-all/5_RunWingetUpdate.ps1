# 5_RunWingetUpdate.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result|WingetLog (Password is always "Redacted")

$State = @'
@state@
'@.Trim()

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()

# Only ever operate on the per-run account created by 1_CreateTempAdmin.ps1
if ($Username -notmatch "^TempWinget_[a-z0-9]{8}$") {
    Write-Error "Refusing to operate on unexpected account name: $Username"
    exit 1
}

# Elevation check for setup
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Elevating setup process..."
}

# Creates a uniquely named working directory that only SYSTEM and Administrators (plus the optional
# accounts in $ModifyAccounts) can access. The protected ACL is applied atomically at creation time,
# so standard users can neither pre-create the folder nor tamper with files placed in it.
function New-ProtectedWorkDir {
    param([string[]]$ModifyAccounts = @())

    $BaseDir = Join-Path $env:windir "LTSvc"
    if (-not (Test-Path $BaseDir)) { $BaseDir = $env:ProgramData }
    $Path = Join-Path $BaseDir ("WingetWork_" + [guid]::NewGuid().ToString("N"))
    if (Test-Path -LiteralPath $Path) { throw "Working directory $Path already exists" }

    $SystemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $Inherit = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $Propagate = [System.Security.AccessControl.PropagationFlags]::None
    $Security = New-Object System.Security.AccessControl.DirectorySecurity
    $Security.SetAccessRuleProtection($true, $false)
    $Security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, "FullControl", $Inherit, $Propagate, "Allow")))
    $Security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($AdminSid, "FullControl", $Inherit, $Propagate, "Allow")))
    foreach ($Account in $ModifyAccounts) {
        $AccountSid = (New-Object System.Security.Principal.NTAccount($Account)).Translate([System.Security.Principal.SecurityIdentifier])
        $Security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($AccountSid, "Modify", $Inherit, $Propagate, "Allow")))
    }

    if ($PSVersionTable.PSEdition -eq "Core") {
        [void][System.IO.FileSystemAclExtensions]::Create((New-Object System.IO.DirectoryInfo($Path)), $Security)
    }
    else {
        [void][System.IO.Directory]::CreateDirectory($Path, $Security)
    }

    # Defense in depth: fail closed if the folder is not ours or is not empty
    $Owner = (Get-Acl -LiteralPath $Path).GetOwner([System.Security.Principal.SecurityIdentifier])
    $CurrentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    if (-not ($Owner.Equals($SystemSid) -or $Owner.Equals($AdminSid) -or $Owner.Equals($CurrentSid))) { throw "Working directory $Path has unexpected owner $Owner" }
    if (Get-ChildItem -LiteralPath $Path -Force) { throw "Working directory $Path is not empty" }
    return $Path
}

$Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

# Unbiased random integer in [0, Maximum) from the cryptographic RNG (rejection sampling)
function Get-SecureRandomInt {
    param([int]$Maximum)
    $Bytes = New-Object byte[] 4
    $Limit = [uint32]::MaxValue - ([uint32]::MaxValue % $Maximum)
    do {
        $Rng.GetBytes($Bytes)
        $Value = [BitConverter]::ToUInt32($Bytes, 0)
    } while ($Value -ge $Limit)
    return [int]($Value % $Maximum)
}

function New-RandomPassword {
    param([int]$Length = 24)
    $CharacterSets = @(
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        'abcdefghijklmnopqrstuvwxyz'
        '0123456789'
        '!@#$%^&*()_+'
    )
    $PasswordArray = @()
    foreach ($set in $CharacterSets) {
        $PasswordArray += $set[(Get-SecureRandomInt $set.Length)]
    }
    $AllChars = ($CharacterSets -join "")
    for ($i = $CharacterSets.Count; $i -lt $Length; $i++) {
        $PasswordArray += $AllChars[(Get-SecureRandomInt $AllChars.Length)]
    }
    # Fisher-Yates shuffle
    for ($i = $PasswordArray.Count - 1; $i -gt 0; $i--) {
        $j = Get-SecureRandomInt ($i + 1)
        $temp = $PasswordArray[$i]
        $PasswordArray[$i] = $PasswordArray[$j]
        $PasswordArray[$j] = $temp
    }
    return -join $PasswordArray
}

function Set-TempAdminPassword {
    param([string]$Name, [string]$NewPassword)
    try {
        Set-LocalUser -Name $Name -Password (ConvertTo-SecureString $NewPassword -AsPlainText -Force) -ErrorAction Stop
    }
    catch {
        # ADSI WinNT provider fallback (keeps the password off any process command line)
        $User = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,user"
        $User.SetPassword($NewPassword)
        $User.SetInfo()
    }
}

# Scrambles the password and disables the account as soon as the task is done.
# 6_DisableTempAdmin.ps1 deletes it; this also covers runs where step 6 never executes.
function Lock-TempAdmin {
    param([string]$Name)
    try { Set-TempAdminPassword -Name $Name -NewPassword (New-RandomPassword 24) } catch {}
    try { Disable-LocalUser -Name $Name -ErrorAction Stop }
    catch { Start-Process net.exe -ArgumentList "user `"$Name`" /active:no" -NoNewWindow -Wait -ErrorAction SilentlyContinue }
}

$TaskName = "TempWingetTask_$(Get-Random)"
# Per-run working folder that only SYSTEM and Administrators can write to. The elevated task runs the
# generated script from here, so standard users must not be able to replace it or plant links for the log.
try {
    $WorkDir = New-ProtectedWorkDir
}
catch {
    Write-Error "Failed to create protected working directory: $($_.Exception.Message)"
    exit 1
}

$LogPath = Join-Path -Path $WorkDir -ChildPath "winget-log.txt"
$TempScriptPath = Join-Path -Path $WorkDir -ChildPath "TempWingetUpdate.ps1"

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
    # We execute winget via a child powershell.exe process to bypass Appx alias tracking limitations in Session 0
    function Invoke-WingetCommand {
        param(
            [string[]]`$Arguments
        )

        Write-Output "DEBUG: Running process: `$WingetCmd `$(`$Arguments -join ' ')"

        try {
            # Every token is passed as a single-quoted literal so package IDs can never be parsed as code
            `$QuotedArgs = (@(`$WingetCmd) + `$Arguments | ForEach-Object { "'" + (`$_ -replace "'", "''") + "'" }) -join ' '
            `$PowershellArgs = "-NoProfile -ExecutionPolicy Bypass -Command & `$QuotedArgs"
            `$Proc = Start-Process -FilePath "powershell.exe" -ArgumentList `$PowershellArgs -NoNewWindow -PassThru
            
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
                # Read exit code from powershell process (which propagates winget's exit code)
                `$ExitCode = `$Proc.ExitCode
                if (`$ExitCode -eq `$null) { `$ExitCode = 0 }
                Write-Output "Process exited with code `$ExitCode."
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
        # Pinned version, installed without marking PSGallery as trusted, imported only if Microsoft-signed
        `$WinGetClientVersion = [version]'1.29.380'
        if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client | Where-Object { `$_.Version -eq `$WinGetClientVersion })) {
            Install-PackageProvider -Name 'NuGet' -Force -ErrorAction SilentlyContinue
            Install-Module -Name Microsoft.WinGet.Client -RequiredVersion `$WinGetClientVersion -Repository PSGallery -Force -Confirm:`$false -Scope CurrentUser -ErrorAction SilentlyContinue
        }

        `$WinGetClientModule = Get-Module -ListAvailable Microsoft.WinGet.Client | Where-Object { `$_.Version -eq `$WinGetClientVersion } | Select-Object -First 1
        if (`$WinGetClientModule) {
            `$Signature = Get-AuthenticodeSignature -FilePath `$WinGetClientModule.Path
            if (`$Signature.Status -eq 'Valid' -and `$Signature.SignerCertificate.Subject -like 'CN=Microsoft Corporation,*') {
                Import-Module `$WinGetClientModule.Path -ErrorAction SilentlyContinue
            } else {
                Write-Output "Init Warning: Microsoft.WinGet.Client signature check failed (`$(`$Signature.Status)), module not imported"
            }
        }
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
        Invoke-WingetCommand @("upgrade", "--all", "--accept-package-agreements", "--accept-source-agreements", "--silent", "--disable-interactivity", "--scope", "machine", "--include-unknown")
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
                        Invoke-WingetCommand @("upgrade", "--id", `$AppId, "--accept-package-agreements", "--accept-source-agreements", "--silent", "--disable-interactivity", "--scope", "machine", "--include-unknown")
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
    # Fresh password generated in-process; it is never written to disk or to the script output
    $Password = New-RandomPassword 24
    Set-TempAdminPassword -Name $Username -NewPassword $Password

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
        # Using a clean, escape-free bracket layout to prevent preprocessor backslash-mangling issues
        $WingetLog = $WingetLog -replace "[^][a-zA-Z0-9\p{L}\p{N}\s.,:_/()+-]", ""
        # Condense multiple spaces into one
        $WingetLog = $WingetLog -replace "\s{2,}", " "
        
        if ($WingetLog.Length -gt 2000) { $WingetLog = $WingetLog.Substring(0, 2000) + "..." }
    }

    if (-not $taskFinished -or -not $taskInfo -or $taskInfo.LastTaskResult -ne 0) {
        $lastResult = if ($taskInfo) { $taskInfo.LastTaskResult } else { "Timeout" }
        Write-Error "Winget update task failed. TaskResult: $lastResult. Log: $WingetLog"
        exit 1
    }
    
    Write-Output "5|${Username}|Redacted|WingetUpdated|${WingetLog}"
}
catch {
    Write-Error "Failed to run Winget update: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    Lock-TempAdmin -Name $Username
    $Password = $null
    if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}