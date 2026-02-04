param(
    [Parameter(Mandatory = $true)]
    [string]$State
)

# 5_RunWingetUpdate.ps1 - ConnectWise Automate compatible
# Input: Username|Password
# Output: Username|Password

$Parts = $State.Split('|')
if ($Parts.Count -lt 2) {
    Write-Error "Invalid state string: $State. Expected Username|Password"
    exit 1
}
$Username = $Parts[0].Trim()
$Password = $Parts[1].Trim()

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
$TempScriptPath = Join-Path -Path $WorkDir -ChildPath "TempWingetUpdate_$(Get-Random).ps1"

$UpdateScriptContent = @"
Start-Transcript -Path '$WorkDir\winget-log.txt' -Append
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
    $Settings.ExecutionTimeLimit = New-TimeSpan -Hours 1
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -User $TargetUser -Password $TargetPass -RunLevel Highest -Force | Out-Null
    
    Start-ScheduledTask -TaskName $TaskName
    $timeout = 7200 
    $startTime = Get-Date
    do {
        Start-Sleep -Seconds 10
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task -and $task.State -ne "Running") {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
            break
        }
        if (((Get-Date) - $startTime).TotalSeconds -gt $timeout) { break }
    } while ($true)

    if (-not $taskInfo -or $taskInfo.LastTaskResult -ne 0) {
        Write-Error "Winget update task failed or timed out. Result: " + ($taskInfo.LastTaskResult ?? "Unknown")
        exit 1
    }
    
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Output $State
}
catch {
    Write-Error "Failed to run Winget update: $($_.Exception.Message)"
    exit 1
}
finally {
    Remove-Item -Path $TempScriptPath -Force -ErrorAction SilentlyContinue
}
