# Run-WingetAutomated.ps1 - Master Simulation Script (PowerShell 5.1)
# Simulated wrapper for ConnectWise Automate workflow

$ScriptsDir = Get-Location
$WingetState = ""

function Invoke-ScriptWithState {
    param($ScriptFile, $CurrentState, $InstallApp = "")
    
    $Content = Get-Content (Join-Path $ScriptsDir $ScriptFile) -Raw
    # Simulate @state@ injection using single quotes for literal safety
    $InjectedContent = $Content -replace "'@state@'", "'$CurrentState'"
    
    if (-not [string]::IsNullOrWhiteSpace($InstallApp)) {
        $InjectedContent = $InjectedContent -replace "'@installapp@'", "'$InstallApp'"
    }
    
    $TempFile = Join-Path $env:TEMP "Simulate_$($ScriptFile)"
    $InjectedContent | Out-File $TempFile -Encoding UTF8
    
    try {
        $Result = powershell.exe -File $TempFile -ErrorAction Stop
        if ($LASTEXITCODE -ne 0) { throw "Script failed with exit code $LASTEXITCODE" }
        return $Result
    }
    finally {
        if (Test-Path $TempFile) { Remove-Item $TempFile -Force }
    }
}

Write-Host "--- Starting Winget Automated Update Simulation ---" -ForegroundColor Cyan

# Step 1: Create/Update Temp Admin
Write-Host "Step 1: Create/Update Temp Admin..."
# Step 1 is strictly one line now
$WingetState = powershell.exe -File (Join-Path $ScriptsDir "1_CreateTempAdmin.ps1")
if ($LASTEXITCODE -ne 0) { Write-Error "Step 1 Failed"; exit 1 }
Write-Host "Captured State: $WingetState"

# Step 2: Add to Administrators
Write-Host "Step 2: Add to Administrators..."
$WingetState = Invoke-ScriptWithState "2_AddLocalAdmin.ps1" $WingetState
Write-Host "Captured State: $WingetState"

# Step 3: Grant Logon As Batch
Write-Host "Step 3: Grant SeBatchLogonRight..."
$WingetState = Invoke-ScriptWithState "3_GrantLogonAsBatch.ps1" $WingetState
Write-Host "Captured State: $WingetState"

# Step 4: Enable Account
Write-Host "Step 4: Enable Account..."
$WingetState = Invoke-ScriptWithState "4_EnableAccount.ps1" $WingetState
Write-Host "Captured State: $WingetState"

# Step 5: Run Winget Update (Requires Elevation)
Write-Host "Step 5: Run Winget Update (Wait for background task)..."
$WingetState = Invoke-ScriptWithState "5_RunWingetUpdate.ps1" $WingetState "Google.Chrome"
Write-Host "Captured State (Summary): $($WingetState.Substring(0, [Math]::Min(100, $WingetState.Length)))..."

# Step 5-2: Run Winget User Update (Interactive context)
Write-Host "Step 5-2: Run Winget User Update (Interactive context)..."
$WingetState = Invoke-ScriptWithState "5-2_RunWingetUserUpdate.ps1" $WingetState "Google.Chrome"
Write-Host "Captured State (Summary): $($WingetState.Substring(0, [Math]::Min(100, $WingetState.Length)))..."

# Step 6: Disable Account
Write-Host "Step 6: Disable Account..."
$FinalState = Invoke-ScriptWithState "6_DisableTempAdmin.ps1" $WingetState
Write-Host "Final Result: $FinalState"

Write-Host "--- Simulation Completed ---" -ForegroundColor Green
