# 5-2_RunWingetUserUpdate.ps1 - ConnectWise Automate compatible
# Purpose: Update User-scope apps for the logged-on user without UAC prompts.
# Input/Output: Step|Username|Result|UserWingetLog

$State = @'
@state@
'@.Trim()
$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string."
    exit 1
}
$AdminUser = $Parts[1].Trim()

# 1. Identify all logged-on interactive users (Console + RDP)
$ExplorerProcesses = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'"
$ActiveUsers = @()
foreach ($Proc in $ExplorerProcesses) {
    try {
        $Owner = Invoke-CimMethod -InputObject $Proc -MethodName "GetOwner"
        if ($Owner.ReturnValue -eq 0) {
            $FullUser = "$($Owner.Domain)\$($Owner.User)"
            # Exclude our own TempAdmin
            if ($FullUser -like "*\TempAutomateAdmin") { continue }
            
            # Translate to SID to filter out SYSTEM, LOCAL SERVICE, and NETWORK SERVICE language-agnostically
            try {
                $NtAccount = New-Object System.Security.Principal.NTAccount($Owner.Domain, $Owner.User)
                $Sid = $NtAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
                # SIDs: S-1-5-18 (System), S-1-5-19 (Local Service), S-1-5-20 (Network Service)
                if ($Sid -match "^S-1-5-1[89]$|^S-1-5-20$") {
                    continue
                }
            }
            catch {
                # Fallback to English string matching if translation fails
                if ($FullUser -match "SYSTEM|LOCAL SERVICE|NETWORK SERVICE") {
                    continue
                }
            }
            
            $ActiveUsers += $FullUser
        }
    } catch {}
}
$ActiveUsers = $ActiveUsers | Select-Object -Unique

if ($ActiveUsers.Count -eq 0) {
    Write-Output "5-2|${AdminUser}|NoUserLoggedOn|Skipping user-scope updates."
    exit 0
}

$GlobalLogSummary = @()

foreach ($LoggedOnUser in $ActiveUsers) {
    Write-Host "Processing updates for session: $LoggedOnUser"

$TaskName = "UserWingetUpdate_$([Guid]::NewGuid().ToString('N'))"
$WorkDir = "C:\eworx"
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

$UserLogPath = Join-Path -Path $WorkDir -ChildPath "user-winget-log.txt"
$UserScriptPath = Join-Path -Path $WorkDir -ChildPath "UserWingetUpdate_$([Guid]::NewGuid().ToString('N')).ps1"

if (Test-Path $UserLogPath) { Remove-Item $UserLogPath -Force }

# 2. Create the script to be run contextually as the user
$UserScriptContent = @"
Add-Type -Name Window -Namespace Win32 -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
`$win = (Get-Process -Id `$PID).MainWindowHandle
if (`$win -ne 0) { [Win32.Window]::ShowWindow(`$win, 0) }

Start-Transcript -Path '$UserLogPath' -Append
try {
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
                break
            }
        }
    }

    Write-Output "Running user-scope upgrade for $LoggedOnUser..."
    
    # --- IGNORING LOGIC AND UPGRADE EXECUTION ---
    `$IgnoreFile = "C:\Windows\LTSvc\eworx\winget\ignoredprograms.txt"
    `$IgnoreList = @()
    if (Test-Path `$IgnoreFile) {
        `$IgnoreList = Get-Content `$IgnoreFile | Where-Object { `$_.Trim() -ne "" } | ForEach-Object { `$_.Trim().ToLower() }
        Write-Output "Loaded `$(`$IgnoreList.Count) ignore entries from `$IgnoreFile"
    }

    if (`$IgnoreList.Count -eq 0) {
        Write-Output "No ignore list found or list is empty. Running upgrade --all --scope user..."
        & `$WingetCmd upgrade --all --scope user --accept-package-agreements --accept-source-agreements --silent --include-unknown
    } else {
        Write-Output "Checking for available user upgrades to apply exclusions..."
        `$Upgrades = & `$WingetCmd upgrade --scope user --accept-source-agreements
        
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
                    if ([string]::IsNullOrWhiteSpace(`$Line) -or `$Line -match "upgrades? available") { continue }
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
                        Write-Output "Skipping ignored user application: `$AppName (`$AppId)"
                    } elseif (`$AppId) {
                        Write-Output "Upgrading User App: `$AppName (`$AppId)..."
                        & `$WingetCmd upgrade --id "`$AppId" --scope user --accept-package-agreements --accept-source-agreements --silent --include-unknown
                    }
                }
            } else {
                Write-Output "Could not reliably parse user column headers."
            }
        } else {
            Write-Output "No valid user upgrade data found or no user upgrades available."
        }
    }
} catch {
    Write-Error "User Script Failure: `$(`$_.Exception.Message)"
} finally {
    Stop-Transcript
}
"@

$UserScriptContent | Out-File -FilePath $UserScriptPath -Encoding UTF8

    try {
        # 3. Register task to run AS the logged-on user (Interactive)
        $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$UserScriptPath`""
        $Principal = New-ScheduledTaskPrincipal -UserId $LoggedOnUser -LogonType Interactive
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings -Force | Out-Null
        
        Start-ScheduledTask -TaskName $TaskName
        
        # Wait for completion (timeout 30 mins)
        $timeout = 1800 
        $startTime = Get-Date
        do {
            Start-Sleep -Seconds 10
            $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($task -and $task.State -ne "Running") { break }
            if (((Get-Date) - $startTime).TotalSeconds -gt $timeout) {
                Write-Warning "Task timed out. Stopping task."
                Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
                break
            }
        } while ($true)

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
            # Keep only safe, printable alphanumeric and Unicode letter characters (no single/double quotes, backticks, semicolons, or pipes)
            $CleanStr = $CleanStr -replace "[^][a-zA-Z0-9\p{L}\p{N}\s.,:_/()+-]", ""
            # Condense multiple spaces into one
            $CleanStr = $CleanStr -replace "\s{2,}", " "
            $GlobalLogSummary += "[$LoggedOnUser]: $CleanStr"
        }
    }
    catch {
        Write-Warning "Failed to run User Winget update for ${LoggedOnUser}: $($_.Exception.Message)"
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
    Write-Output "5-2|${AdminUser}|UserAppsUpdated|${FinalUserLog}"
} else {
    Write-Output "5-2|${AdminUser}|NoUpdatesRun|Could not generate logs for users."
}
