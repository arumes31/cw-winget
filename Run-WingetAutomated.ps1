# Master script to automate Winget updates using a temporary administrator

$ScriptDir = $PSScriptRoot
$TempUser = "TempWingetAdmin"

Write-Host "--- Step 1: Creating Temporary Admin ---" -ForegroundColor Cyan
$CreateResult = & "$ScriptDir\1_CreateTempAdmin.ps1" -Username $TempUser 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Step 1 Failed: $CreateResult"
    exit 1
}

$Parts = $CreateResult.ToString().Split('|')
if ($Parts.Count -ne 2) {
    Write-Error "Failed to parse credentials from Step 1. Output: $CreateResult"
    exit 1
}

$Username = $Parts[0].Trim()
$Password = $Parts[1].Trim()

Write-Host "User created: $Username"

try {
    Write-Host "--- Step 2: Adding to Local Admins ---" -ForegroundColor Cyan
    & "$ScriptDir\2_AddLocalAdmin.ps1" -Username $Username
    if ($LASTEXITCODE -ne 0) { throw "Step 2 Failed" }

    Write-Host "--- Step 3: Granting Logon as Batch Job ---" -ForegroundColor Cyan
    & "$ScriptDir\3_GrantLogonAsBatch.ps1" -Username $Username
    if ($LASTEXITCODE -ne 0) { throw "Step 3 Failed" }

    Write-Host "--- Step 4: Enabling Account ---" -ForegroundColor Cyan
    & "$ScriptDir\4_EnableAccount.ps1" -Username $Username
    if ($LASTEXITCODE -ne 0) { throw "Step 4 Failed" }

    Write-Host "--- Step 5: Running Winget Update ---" -ForegroundColor Cyan
    & "$ScriptDir\5_RunWingetUpdate.ps1" -Username $Username -Password $Password
    if ($LASTEXITCODE -ne 0) { throw "Step 5 Failed" }

}
catch {
    Write-Error "Automation failed: $($_.Exception.Message)"
}
finally {
    Write-Host "--- Step 6: Removing Temporary Admin ---" -ForegroundColor Cyan
    & "$ScriptDir\6_RemoveTempAdmin.ps1" -Username $Username
}

Write-Host "Automation sequence finished." -ForegroundColor Green
