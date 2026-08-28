# Run-WingetAutomated.ps1 - local simulation of the ConnectWise Automate workflow.

$ScriptsDir = $PSScriptRoot
$WingetState = ""

function Invoke-ScriptWithState {
    param(
        [Parameter(Mandatory)][string]$ScriptFile,
        [Parameter(Mandatory)][string]$CurrentState
    )

    $content = Get-Content (Join-Path $ScriptsDir $ScriptFile) -Raw
    $injectedContent = $content.Replace("'@state@'", "'$CurrentState'")
    $tempFile = Join-Path $env:TEMP "cw-winget-$([Guid]::NewGuid().ToString('N')).ps1"
    $injectedContent | Out-File $tempFile -Encoding UTF8
    try {
        $result = & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $tempFile
        if ($LASTEXITCODE -ne 0) { throw "$ScriptFile failed with exit code $LASTEXITCODE" }
        return $result
    }
    finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "--- Starting Winget Automated Update Simulation ---" -ForegroundColor Cyan
try {
    Write-Host "Step 1: Create disabled temporary admin..."
    $WingetState = & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File (Join-Path $ScriptsDir "1_CreateTempAdmin.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Step 1 failed with exit code $LASTEXITCODE" }

    Write-Host "Step 2: Add to Administrators..."
    $WingetState = Invoke-ScriptWithState -ScriptFile "2_AddLocalAdmin.ps1" -CurrentState $WingetState

    Write-Host "Step 3: Grant SeBatchLogonRight..."
    $WingetState = Invoke-ScriptWithState -ScriptFile "3_GrantLogonAsBatch.ps1" -CurrentState $WingetState

    Write-Host "Step 4: Verify the account remains disabled..."
    $WingetState = Invoke-ScriptWithState -ScriptFile "4_EnableAccount.ps1" -CurrentState $WingetState

    Write-Host "Step 5: Run machine-scope Winget update..."
    $WingetState = Invoke-ScriptWithState -ScriptFile "5_RunWingetUpdate.ps1" -CurrentState $WingetState

    Write-Host "Step 5-2: Run user-scope Winget update..."
    $WingetState = Invoke-ScriptWithState -ScriptFile "5-2_RunWingetUserUpdate.ps1" -CurrentState $WingetState

    Write-Host "--- Simulation Completed ---" -ForegroundColor Green
}
finally {
    # Use a fixed password-free state so cleanup still runs when any prior step failed.
    $cleanupState = "6|TempAutomateAdmin|EmergencyCleanup"
    try {
        $cleanupResult = Invoke-ScriptWithState -ScriptFile "6_DisableTempAdmin.ps1" -CurrentState $cleanupState
        Write-Host "Cleanup result: $cleanupResult"
    }
    catch {
        Write-Error "Emergency cleanup failed: $($_.Exception.Message)"
    }
}
