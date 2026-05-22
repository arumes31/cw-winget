# 5-2_RunWingetUserUpdate.ps1 - ConnectWise Automate compatible
# Purpose: Update User-scope apps for the logged-on user without UAC prompts.
# Input/Output: Step|Username|Password|Result|UserWingetLog

$State = @'
@state@
'@.Trim()
$installapp = '@installapp@'

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string."
    exit 1
}
$AdminUser = $Parts[1].Trim()
$AdminPass = $Parts[2].Trim()

# 1. Identify all logged-on interactive users (Console + RDP) using offline-safe CIM/WMI methods
$ExplorerProcesses = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'"
$ActiveUsers = @()
foreach ($Proc in $ExplorerProcesses) {
    try {
        # Retrieve the security token owner's SID directly from the process (doesn't contact the Domain Controller)
        $OwnerSidResult = Invoke-CimMethod -InputObject $Proc -MethodName "GetOwnerSid"
        if ($OwnerSidResult.ReturnValue -eq 0 -and -not [string]::IsNullOrEmpty($OwnerSidResult.Sid)) {
            $Sid = $OwnerSidResult.Sid
            
            # SIDs: S-1-5-18 (SYSTEM), S-1-5-19 (LOCAL SERVICE), S-1-5-20 (NETWORK SERVICE)
            if ($Sid -match "^S-1-5-1[89]$|^S-1-5-20$") {
                continue
            }
            
            # Retrieve the username (Domain\User)
            $Owner = Invoke-CimMethod -InputObject $Proc -MethodName "GetOwner"
            $FullUser = if ($Owner.ReturnValue -eq 0) { "$($Owner.Domain)\$($Owner.User)" } else { $Sid }
            
            # Exclude our own TempAdmin
            if ($FullUser -like "*\TempAutomateAdmin") { continue }
            
            $ActiveUsers += [PSCustomObject]@{
                Username = $FullUser
                Sid      = $Sid
            }
        }
    } catch {}
}
$ActiveUsers = $ActiveUsers | Group-Object Username | ForEach-Object { $_.Group[0] }

if ($ActiveUsers.Count -eq 0) {
    Write-Output "5-2|${AdminUser}|${AdminPass}|NoUserLoggedOn|Skipping user-scope updates."
    exit 0
}

$GlobalLogSummary = @()

foreach ($UserObj in $ActiveUsers) {
    $LoggedOnUser = $UserObj.Username
    $UserSid = $UserObj.Sid
    Write-Host "Processing updates for session: $LoggedOnUser"

$TaskName = "UserWingetUpdate_$(Get-Random)"
$WorkDir = "C:\eworx"
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

try {
    # Set ACL rule using the SecurityIdentifier (SID) object directly to prevent Domain Controller resolution locks
    $Acl = Get-Acl $WorkDir
    $UserSidObj = New-Object System.Security.Principal.SecurityIdentifier($UserSid)
    $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($UserSidObj, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $Acl.SetAccessRule($Ar)
    Set-Acl $WorkDir $Acl
} catch {
    Write-Warning "Failed to set ACL on $WorkDir for $LoggedOnUser ($UserSid) - $($_.Exception.Message)"
}
$UserLogPath = Join-Path -Path $WorkDir -ChildPath "user-winget-log.txt"
$UserScriptPath = Join-Path -Path $WorkDir -ChildPath "UserWingetUpdate_$(Get-Random).ps1"

if (Test-Path $UserLogPath) { Remove-Item $UserLogPath -Force }

# 2. Create the script to be run contextually as the user (using single-quoted here-string for safety)
$UserScriptContent = @'
Start-Transcript -Path '__USER_LOG_PATH__' -Append
try {
    function Invoke-WingetSilent {
        param(
            [string]${Arguments},
            [bool]$CaptureOutput = $false
        )
        
        $TempFile = Join-Path $env:TEMP "winget_out_$(Get-Random).txt"
        try {
            $CmdLine = """$WingetCmd"" ${Arguments} > ""$TempFile"" 2>&1"
            $Psi = New-Object System.Diagnostics.ProcessStartInfo
            $Psi.FileName = "cmd.exe"
            $Psi.Arguments = "/c ""$CmdLine"""
            $Psi.UseShellExecute = $false
            $Psi.CreateNoWindow = $true
            
            $Process = [System.Diagnostics.Process]::Start($Psi)
            $Process.WaitForExit()
            
            if (Test-Path $TempFile) {
                $Content = Get-Content $TempFile
                Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
                if ($CaptureOutput) {
                    return $Content
                } else {
                    foreach ($Line in $Content) {
                        Write-Output $Line
                    }
                }
            }
        } catch {
            Write-Error "Failed running winget ${Arguments}: $($_.Exception.Message)"
        }
    }

    $WingetCmd = "winget"
    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        $PotentialPaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe",
            "$env:USERPROFILE\AppData\Local\Microsoft\WindowsApps\winget.exe"
        )
        foreach ($Path in $PotentialPaths) {
            $ResolvedPath = Resolve-Path $Path -ErrorAction SilentlyContinue
            if ($ResolvedPath) {
                $WingetCmd = $ResolvedPath.Path
                break
            }
        }
    }

    $installapp = '__INSTALL_APP__'
    if ($installapp) { $installapp = $installapp.Trim() }
    $sentinel = "@" + "installapp" + "@"
    
    if (-not [string]::IsNullOrWhiteSpace($installapp) -and $installapp -ne $sentinel) {
        Write-Output "Running user-scope install/update for $installapp..."
        Invoke-WingetSilent "install --id $installapp --exact --scope user --accept-package-agreements --accept-source-agreements --silent --include-unknown"
    } else {
        Write-Output "Running user-scope upgrade all fallback..."

        # --- IGNORING LOGIC AND UPGRADE EXECUTION ---
        $IgnoreFile = "C:\Windows\LTSvc\eworx\winget\ignoredprograms.txt"
        $IgnoreList = @()
        if (Test-Path $IgnoreFile) {
            $IgnoreList = Get-Content $IgnoreFile | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim().ToLower() }
            Write-Output "Loaded $($IgnoreList.Count) ignore entries from $IgnoreFile"
        }

        if ($IgnoreList.Count -eq 0) {
            Write-Output "No ignore list found or list is empty. Running upgrade --all --scope user..."
            Invoke-WingetSilent "upgrade --all --scope user --accept-package-agreements --accept-source-agreements --silent --include-unknown"
        } else {
            Write-Output "Checking for available user upgrades to apply exclusions..."
            $Upgrades = Invoke-WingetSilent "upgrade --scope user --accept-source-agreements" -CaptureOutput $true
            
            # LANGUAGE-AGNOSTIC PARSING: Find the dashed line to identify headers and columns
            $DashLine = $Upgrades | Where-Object { $_ -match "^-{10,}" } | Select-Object -First 1
            $DashIndex = [array]::IndexOf($Upgrades, $DashLine)

            if ($DashIndex -gt 0 -and $DashIndex -lt ($Upgrades.Count - 1)) {
                $HeaderLine = $Upgrades[$DashIndex - 1]
                $HeaderParts = $HeaderLine -split '\s{2,}'
                
                if ($HeaderParts.Count -ge 3) {
                    $IdHeader = $HeaderParts[1]
                    $VersionHeader = $HeaderParts[2]
                    
                    $IdStart = $HeaderLine.IndexOf($IdHeader)
                    $VersionStart = $HeaderLine.IndexOf($VersionHeader)
                    $IdLength = $VersionStart - $IdStart

                    for ($i = $DashIndex + 1; $i -lt $Upgrades.Count; $i++) {
                        $Line = $Upgrades[$i]
                        if ([string]::IsNullOrWhiteSpace($Line) -or $Line -match "upgrades? available") { continue }
                        if ($Line.Length -lt $IdStart) { continue }
                        
                        $AppName = $Line.Substring(0, $IdStart).Trim()
                        $AppId = ""
                        if ($Line.Length -ge $VersionStart) {
                            $AppId = $Line.Substring($IdStart, $IdLength).Trim()
                        } else {
                            $AppId = $Line.Substring($IdStart).Trim()
                        }
                        
                        # Skip summary/warning lines that might be parsed on localized systems
                        if ($AppId.Contains(" ") -or $AppId -match "\s") { continue }
                        
                        $Skip = $false
                        foreach ($IgnoreItem in $IgnoreList) {
                            if ($AppName.ToLower().Contains($IgnoreItem) -or $AppId.ToLower().Contains($IgnoreItem)) {
                                $Skip = $true
                                break
                            }
                        }
                        
                        if ($Skip) {
                            Write-Output "Skipping ignored user application: $AppName ($AppId)"
                        } elseif ($AppId) {
                            Write-Output "Upgrading User App: $AppName ($AppId)..."
                            Invoke-WingetSilent "upgrade --id '$AppId' --scope user --accept-package-agreements --accept-source-agreements --silent --include-unknown"
                        }
                    }
                } else {
                    Write-Output "Could not reliably parse user column headers."
                }
            } else {
                Write-Output "No valid user upgrade data found or no user upgrades available."
            }
        }
    }
} catch {
    Write-Error "User Script Failure: $($_.Exception.Message)"
} finally {
    Stop-Transcript
}
'@

# Replace template placeholders
$UserScriptContent = $UserScriptContent.Replace('__USER_LOG_PATH__', $UserLogPath)
$UserScriptContent = $UserScriptContent.Replace('__INSTALL_APP__', $installapp)

$UserScriptContent | Out-File -FilePath $UserScriptPath -Encoding UTF8

    try {
        # 3. Register task to run AS the logged-on user (Interactive) using powershell.exe directly with Hidden window style
        # This completely bypasses the need for wscript.exe and .vbs launchers, avoiding corporate Windows Script Host disabling policies
        $PowershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path $PowershellPath)) { $PowershellPath = "powershell.exe" }
        $Action = New-ScheduledTaskAction -Execute $PowershellPath -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$UserScriptPath`""
        
        $Principal = New-ScheduledTaskPrincipal -UserId $UserSid -LogonType Interactive
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings -Force | Out-Null
        
        Start-ScheduledTask -TaskName $TaskName
        
        # Wait for completion (timeout 30 mins)
        $timeout = 1800 
        $startTime = Get-Date
        do {
            Start-Sleep -Seconds 10
            $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            if (-not $task) {
                Write-Warning "Scheduled task $TaskName not found."
                break
            }
            if ($task.State -ne "Running") { break }
            if (((Get-Date) - $startTime).TotalSeconds -gt $timeout) {
                Write-Warning "Task timed out. Stopping task."
                Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
                break
            }
        } while ($true)

        # Retrieve scheduled task info to check LastTaskResult
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        $LastResult = if ($taskInfo) { $taskInfo.LastTaskResult } else { "Unknown" }

        # 4. Process Logs
        if (Test-Path $UserLogPath) {
            $RawLog = Get-Content $UserLogPath
            $CleanLog = @()
            $InBlock = $false
            foreach ($line in $RawLog) {
                if ($line -match "^\*\*\*\*") { $InBlock = -not $InBlock; continue }
                if (-not $InBlock -and $line.Trim()) { $CleanLog += $line.Trim() }
            }
            $CleanStr = $CleanLog -join " "
            # Replace newlines and carriage returns with spaces first
            $CleanStr = $CleanStr -replace "[\r\n]+", " "
            # Keep safe alphanumeric/Unicode characters AND backslashes (\\) so paths and domains remain valid (excluding dangerous delimiters like quotes/pipes)
            $CleanStr = $CleanStr -replace "[^][a-zA-Z0-9\p{L}\p{N}\s.,:_/()+\-\\ ]", ""
            # Condense multiple spaces into one
            $CleanStr = $CleanStr -replace "\s{2,}", " "
            $GlobalLogSummary += "[$LoggedOnUser]: $CleanStr"
        } else {
            $GlobalLogSummary += "[$LoggedOnUser]: ERROR - Log file not generated (TaskResult: $LastResult)"
        }
    }
    catch {
        $ErrorMsg = "Failed to run User Winget update for ${LoggedOnUser} - $($_.Exception.Message)"
        Write-Output $ErrorMsg
        $GlobalLogSummary += "[$LoggedOnUser]: ERROR - $($_.Exception.Message)"
    }
    finally {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        if (Test-Path $UserScriptPath) { Remove-Item -Path $UserScriptPath -Force -ErrorAction SilentlyContinue }
    }
} # End of User Loop

if ($GlobalLogSummary.Count -gt 0) {
    $FinalUserLog = $GlobalLogSummary -join " | "
    if ($FinalUserLog.Length -gt 2000) { $FinalUserLog = $FinalUserLog.Substring(0, 2000) + "..." }
    Write-Output "5-2|${AdminUser}|${AdminPass}|UserAppsUpdated|${FinalUserLog}"
} else {
    Write-Output "5-2|${AdminUser}|${AdminPass}|NoUpdatesRun|Could not generate logs for users."
}
