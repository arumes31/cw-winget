# 5_RunWingetUpdate.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result|WingetLog

$State = '@state@'
$installapp = '@installapp@'

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()
$Password = $Parts[2].Trim()

Write-Host "DEBUG: Outer installapp value: '$installapp'"

# Elevation check for setup
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Elevating setup process..."
}

$TaskName = "TempWingetTask_$(Get-Random)"
$WorkDir = "C:\eworx"
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

# Explicitly grant Edit permission to Administrators (which Includes TempAutomateAdmin) 
# to ensure Start-Transcript and File operations work within the Scheduled Task
try {
    $Acl = Get-Acl $WorkDir
    $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
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
    function Test-IsAdmin {
        `$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        `$principal = New-Object Security.Principal.WindowsPrincipal(`$currentUser)
        return `$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    # Deep Initialization for WinGet in new user profile
    try {
        # Ensure module is available
        if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client)) {
            Install-PackageProvider -Name 'NuGet' -Force -ErrorAction SilentlyContinue
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            # Fix: Using CurrentUser scope to avoid Administrator rights requirement for AllUsers
            Install-Module -Name Microsoft.WinGet.Client -Force -Confirm:`$false -Scope CurrentUser -ErrorAction SilentlyContinue
        }
        
        # Repair/Register WinGet for the current user session
        Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
        if (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue) {
            # Removing -Scope as it's not supported in all module versions
            Repair-WinGetPackageManager -ErrorAction SilentlyContinue
        }
        
        # Register the AppInstaller itself for this user
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
    } catch {
        Write-Output "Init Warning: `$(`$_.Exception.Message)"
    }

    # Robust WinGet command discovery
    `$WingetCmd = "winget"
    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        `$PotentialPaths = @(
            "`$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "`$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
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

    # Direct Source Injection (User Suggestion)
    # This bypasses potential download/caching issues by installing the source package directly
    Add-AppxPackage -Path "https://cdn.winget.microsoft.com/cache/source.msix" -ErrorAction SilentlyContinue

    # Reset and Update
    & `$WingetCmd source reset --force
    & `$WingetCmd source update

    # Stabilization delay to ensure source index is flushed to disk
    Start-Sleep -Seconds 10


    # Pass variables from outer scope to inner scope
    `$installapp = '$installapp'
    Write-Output "DEBUG: Inner installapp value: '`$installapp'"

    # Sanitize
    if (`$installapp) { `$installapp = `$installapp.Trim() }

    `$checkNull = [string]::IsNullOrWhiteSpace(`$installapp)
    # Construct sentinel at runtime to avoid replacement by CWA/Simulator
    `$sentinel = "@" + "installapp" + "@"
    `$checkPlaceholder = (`$installapp -eq `$sentinel)
    Write-Output "DEBUG: CheckNull=`$checkNull, CheckPlaceholder=`$checkPlaceholder"

    # Check and Install/Update Specific App
    if (-not `$checkNull -and -not `$checkPlaceholder) {
        Write-Output "Checking for application: `$installapp"
        # Try to find the package first
        `$searchResult = & `$WingetCmd search --id `$installapp --accept-source-agreements
        
        if (`$LASTEXITCODE -eq 0) {
            Write-Output "Installing/Updating application: `$installapp"
            # We use install because it handles both fresh install and upgrade for most packages
            & `$WingetCmd install --id `$installapp --exact --accept-package-agreements --accept-source-agreements --scope machine --force --silent
        } else {
            Write-Warning "Application '`$installapp' not found in sources."
        }
    } else {
        Write-Warning "No application specified in installapp variable."
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
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TempScriptPath`""
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
        if (((Get-Date) - $startTime).TotalSeconds -gt $timeout) { break }
    } while ($true)

    $WingetLog = "No log found"
    if (Test-Path $LogPath) {
        $RawLog = Get-Content $LogPath
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
            $_ -notmatch "^End time:" -and
            $_ -notmatch "o{10,}" -and # Match long progress bars (10+ o's)
            $_ -notmatch "^Deployment operation progress" -and
            $_ -notmatch "^Updating source:" -and
            $_ -notmatch "^Resetting all sources" -and
            $_ -notmatch "^The 'msstore' source requires" -and
            $_ -notmatch "^Terms of Transaction" -and
            $_ -notmatch "^The source requires the current machine" -and
            $_ -notmatch "^usage: winget" -and
            $_ -notmatch "^The following arguments are available:" -and
            $_ -notmatch "^The following options are available:" -and
            $_ -notmatch "^The following command aliases are available" -and
            $_ -notmatch "^Prompts the user to press any key" -and
            $_ -notmatch "^--logs,--open-logs" -and
            $_ -notmatch "^--verbose,--verbose-logs" -and
            $_ -notmatch "^--nowarn,--ignore-warnings" -and
            $_ -notmatch "^--disable-interactivity" -and
            $_ -notmatch "^--proxy" -and
            $_ -notmatch "^--no-proxy" -and
            $_.Trim() -ne ""
        }
        $WingetLog = $CleanLog -join " ; "
        $WingetLog = $WingetLog -replace "\|", "/" 
        if ($WingetLog.Length -gt 2000) { $WingetLog = $WingetLog.Substring(0, 2000) + "..." }
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
