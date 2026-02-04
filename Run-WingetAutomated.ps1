# Master script to simulate ConnectWise Automate workflow locally
# Uses the Username|Password string passing pattern.

$ScriptDir = $PSScriptRoot

Write-Host "--- Step 1: Creating Temporary Admin ---" -ForegroundColor Cyan
$State = & "$ScriptDir\1_CreateTempAdmin.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "State: $State"

Write-Host "--- Step 2: Adding to Local Admins ---" -ForegroundColor Cyan
$State = & "$ScriptDir\2_AddLocalAdmin.ps1" -State $State
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "--- Step 3: Granting Logon as Batch Job ---" -ForegroundColor Cyan
$State = & "$ScriptDir\3_GrantLogonAsBatch.ps1" -State $State
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "--- Step 4: Enabling Account ---" -ForegroundColor Cyan
$State = & "$ScriptDir\4_EnableAccount.ps1" -State $State
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "--- Step 5: Running Winget Update ---" -ForegroundColor Cyan
$State = & "$ScriptDir\5_RunWingetUpdate.ps1" -State $State
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "--- Step 6: Removing Temporary Admin ---" -ForegroundColor Cyan
& "$ScriptDir\6_RemoveTempAdmin.ps1" -State $State

Write-Host "Automation sequence finished." -ForegroundColor Green
