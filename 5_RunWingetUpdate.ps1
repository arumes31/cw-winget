# 5_RunWingetUpdate.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result|WingetLog

$State = "@state@"

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string: ${State}. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()
$Password = $Parts[2].Trim()

# Check if running as Administrator for script setup
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Script 5 must be run as Administrator."
    exit 1
}

$TargetUser = $Username -replace '\s+', ''
$TargetPass = $Password -replace '\s+', ''

$TaskName = "TempWingetTask_$(Get-Random)"
$WorkDir = "C:\eworx"
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
$LogPath = Join-Path -Path $WorkDir -ChildPath "winget-log.txt"
$TempScriptPath = Join-Path -Path $WorkDir -ChildPath "TempWingetUpdate_$(Get-Random).ps1"

# Clear old log
if (Test-Path $LogPath) { Remove-Item $LogPath -Force }

$UpdateScriptContent = @"
Start-Transcript -Path '$LogPath' -Append
function Test-IsAdmin {
    `$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    `$principal = New-Object Security.Principal.WindowsPrincipal(`$currentUser)
    return `$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (Test-IsAdmin) {
    Install-PackageProvider -Name 'NuGet' -Force -ErrorAction SilentlyContinue
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    try {
        if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client)) {
            Install-Module -Name Microsoft.WinGet.Client -Force -Confirm:`$false -Scope AllUsers -ErrorAction Stop
        }
        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop
    } catch {
        Write-Output 'Repair failed: ' + `$_.Exception.Message
    }
    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
}
& winget upgrade --all --accept-package-agreements --accept-source-agreements --silent
Stop-Transcript
"@

$UpdateScriptContent | Out-File -FilePath $TempScriptPath -Encoding UTF8

try {
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TempScriptPath`""
    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date)
    
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -User $TargetUser -Password $TargetPass -RunLevel Highest -Force | Out-Null
    
    Start-ScheduledTask -TaskName $TaskName
    
    # Wait for task completion (maximum 2 hours)
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
        if (((Get-Date) - $startTime).TotalSeconds -gt $timeout) { break }
    } while ($true)

    $WingetLog = "No log found"
    if (Test-Path $LogPath) {
        $RawLog = Get-Content $LogPath
        # Filter out transcript headers/footers and noise
        $CleanLog = $RawLog | Where-Object { 
            $_ -notmatch "^\*\*\*\*" -and 
            $_ -notmatch "^Windows PowerShell transcript" -and
            $_ -notmatch "^Start time:" -and
            $_ -notmatch "^Username:" -and
            $_ -notmatch "^RunAs User:" -and
            $_ -notmatch "^Configuration Name:" -and
            $_ -notmatch "^Machine:" -and
            $_ -notmatch "^Host Application:" -and
            $_ -notmatch "^Process ID:" -and
            $_ -notmatch "^PSVersion:" -and
            $_ -notmatch "^PSEdition:" -and
            $_ -notmatch "^PSCompatibleVersions:" -and
            $_ -notmatch "^BuildVersion:" -and
            $_ -notmatch "^CLRVersion:" -and
            $_ -notmatch "^WSManStackVersion:" -and
            $_ -notmatch "^PSRemotingProtocolVersion:" -and
            $_ -notmatch "^SerializationVersion:" -and
            $_ -notmatch "^Transcript started" -and
            $_.Trim() -ne ""
        }
        $WingetLog = $CleanLog -join " ; "
        $WingetLog = $WingetLog -replace "\|", "/" # Clean for state string
        if ($WingetLog.Length -gt 1000) { $WingetLog = $WingetLog.Substring(0, 1000) + "..." }
    }

    if (-not $taskFinished -or -not $taskInfo -or $taskInfo.LastTaskResult -ne 0) {
        $lastResult = if ($taskInfo) { $taskInfo.LastTaskResult } else { "Timeout" }
        Write-Error "Winget update task failed. TaskResult: $lastResult. Log: $WingetLog"
        exit 1
    }
    
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Output "5|${Username}|${Password}|WingetUpdated|${WingetLog}"
}
catch {
    Write-Error "Failed to run Winget update: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path $TempScriptPath) { Remove-Item -Path $TempScriptPath -Force -ErrorAction SilentlyContinue }
}
