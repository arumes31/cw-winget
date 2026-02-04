# Master script to simulate ConnectWise Automate workflow locally
# Mirrors the Step|Username|Password|Result string passing pattern with injection simulation.

$ScriptDir = $PSScriptRoot

function Run-ScriptWithState {
    param([string]$File, [string]$CurrentState)
    $Content = Get-Content $File -Raw
    $InjectedContent = $Content -replace '@state@', $CurrentState
    $TempFile = Join-Path $env:TEMP "injected_$(Get-Random).ps1"
    $InjectedContent | Set-Content $TempFile
    try {
        & $TempFile
    }
    finally {
        Remove-Item $TempFile -ErrorAction SilentlyContinue
    }
}

Write-Host "--- Step 1: Managing Temporary Admin (Create/Update) ---" -ForegroundColor Cyan
# Step 1 doesn't use @state@ as it initiates it
$State = & "${ScriptDir}\1_CreateTempAdmin.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "Current State: ${State}"

Write-Host "--- Step 2: Adding to Local Admins ---" -ForegroundColor Cyan
$State = Run-ScriptWithState -File "${ScriptDir}\2_AddLocalAdmin.ps1" -CurrentState "${State}"
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "Current State: ${State}"

Write-Host "--- Step 3: Granting Logon as Batch Job ---" -ForegroundColor Cyan
$State = Run-ScriptWithState -File "${ScriptDir}\3_GrantLogonAsBatch.ps1" -CurrentState "${State}"
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "Current State: ${State}"

Write-Host "--- Step 4: Enabling Account ---" -ForegroundColor Cyan
$State = Run-ScriptWithState -File "${ScriptDir}\4_EnableAccount.ps1" -CurrentState "${State}"
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "Current State: ${State}"

Write-Host "--- Step 5: Running Winget Update ---" -ForegroundColor Cyan
$State = Run-ScriptWithState -File "${ScriptDir}\5_RunWingetUpdate.ps1" -CurrentState "${State}"
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "Current State: ${State}"

Write-Host "--- Step 6: Disabling Temporary Admin ---" -ForegroundColor Cyan
$State = Run-ScriptWithState -File "${ScriptDir}\6_DisableTempAdmin.ps1" -CurrentState "${State}"
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "Final State: ${State}"

Write-Host "Automation sequence finished." -ForegroundColor Green
