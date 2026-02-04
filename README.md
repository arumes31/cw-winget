# Winget Automated Update Utility (ConnectWise Automate)

This utility is designed to run in a ConnectWise Automate workflow. It uses a single variable to pass state (credentials) between script steps.

## ConnectWise Automate Integration

1.  **Step 1**: Run `1_CreateTempAdmin.ps1`. Store 'PowerShell Script Result' in a variable like `%WingetCreds%`.
2.  **Step 2**: Run `2_AddLocalAdmin.ps1 -State "%WingetCreds%"`. Update `%WingetCreds%` with the result.
3.  **Step 3**: Run `3_GrantLogonAsBatch.ps1 -State "%WingetCreds%"`. Update `%WingetCreds%` with the result.
4.  **Step 4**: Run `4_EnableAccount.ps1 -State "%WingetCreds%"`. Update `%WingetCreds%` with the result.
5.  **Step 5**: Run `5_RunWingetUpdate.ps1 -State "%WingetCreds%"`. Update `%WingetCreds%` with the result. (Ensure this step runs as Admin).
6.  **Step 6**: Run `6_RemoveTempAdmin.ps1 -State "%WingetCreds%"`.

## Scripts

- **1_CreateTempAdmin.ps1**: Creates user, outputs `Username|Password`.
- **2_AddLocalAdmin.ps1**: Adds user to local admins.
- **3_GrantLogonAsBatch.ps1**: Grants 'Logon as batch job'.
- **4_EnableAccount.ps1**: Enables the account.
- **5_RunWingetUpdate.ps1**: Runs winget upgrades via a temporary Scheduled Task.
- **6_RemoveTempAdmin.ps1**: Deletes the temporary user.

## PowerShell Compatibility

- Fully supports **PowerShell 5.1**.
- Handles UTF-16 encoding quirks of `secedit`.
- Robust winget bootstrap (Repair-WinGetPackageManager).
