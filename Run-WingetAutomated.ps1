# Master script to automate Winget updates using a temporary administrator
# Ensures PowerShell 5.1 compatibility and handles data flow via a single state variable.

$ScriptDir = $PSScriptRoot

# The "Single Var" to hold state
$AutomationState = @{
    Username = "TempWingetAdmin"
    Password = $null
    Error    = $null
    Status   = "Starting"
}

Write-Host "--- Step 1: Creating Temporary Admin ---" -ForegroundColor Cyan
# Script 1 takes the state, modifies it, and returns the updated state
$AutomationState = & "$ScriptDir\1_CreateTempAdmin.ps1" -State $AutomationState
if ($AutomationState.Error) {
    Write-Error "Step 1 Failed: $($AutomationState.Error)"
    exit 1
}

Write-Host "User created: $($AutomationState.Username)"

try {
    Write-Host "--- Step 2: Adding to Local Admins ---" -ForegroundColor Cyan
    $AutomationState = & "$ScriptDir\2_AddLocalAdmin.ps1" -State $AutomationState
    if ($AutomationState.Error) { throw $AutomationState.Error }

    Write-Host "--- Step 3: Granting Logon as Batch Job ---" -ForegroundColor Cyan
    $AutomationState = & "$ScriptDir\3_GrantLogonAsBatch.ps1" -State $AutomationState
    if ($AutomationState.Error) { throw $AutomationState.Error }

    Write-Host "--- Step 4: Enabling Account ---" -ForegroundColor Cyan
    $AutomationState = & "$ScriptDir\4_EnableAccount.ps1" -State $AutomationState
    if ($AutomationState.Error) { throw $AutomationState.Error }

    Write-Host "--- Step 5: Running Winget Update ---" -ForegroundColor Cyan
    $AutomationState = & "$ScriptDir\5_RunWingetUpdate.ps1" -State $AutomationState
    if ($AutomationState.Error) { throw $AutomationState.Error }

}
catch {
    Write-Error "Automation failed: $($_.Exception.Message)"
}
finally {
    Write-Host "--- Step 6: Removing Temporary Admin ---" -ForegroundColor Cyan
    $AutomationState = & "$ScriptDir\6_RemoveTempAdmin.ps1" -State $AutomationState
}

Write-Host "Automation sequence finished." -ForegroundColor Green
