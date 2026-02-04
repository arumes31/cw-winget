param(
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [Parameter(Mandatory = $true)]
    [string]$Password
)

$TaskName = "WingetUpdateTask"
$Command = "powershell.exe"
$Args = "-NoProfile -ExecutionPolicy Bypass -Command `"winget upgrade --all --accept-source-agreements --accept-package-agreements`""

try {
    Write-Host "Creating scheduled task to run winget as $Username..."
    
    $Action = New-ScheduledTaskAction -Execute $Command -Argument $Args
    $Principal = New-ScheduledTaskPrincipal -UserId $Username -LogonType Password
    
    # Register the task with the password
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Force | Out-Null
    
    # We need to set the password after registration if using New-ScheduledTaskPrincipal with UserId
    # Or just use the Set-ScheduledTask with -Password
    $st = Get-ScheduledTask -TaskName $TaskName
    $st.Principal.LogonType = "Password"
    Set-ScheduledTask -InputObject $st -User $Username -Password $Password | Out-Null

    Write-Host "Starting winget update task..."
    Start-ScheduledTask -TaskName $TaskName

    Write-Host "Waiting for winget update to complete..."
    do {
        Start-Sleep -Seconds 5
        $Task = Get-ScheduledTask -TaskName $TaskName
    } while ($Task.State -eq "Running")

    Write-Host "Winget update task finished with state: $($Task.State)"
}
catch {
    Write-Error "Failed to execute winget update: $($_.Exception.Message)"
}
finally {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Scheduled task $TaskName removed."
    }
}
