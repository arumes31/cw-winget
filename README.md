# Winget Automated Update Utility (ConnectWise Automate)

This utility is designed to run in a ConnectWise Automate workflow. It uses a single variable to pass state (credentials and status) between script steps.

## ConnectWise Automate Integration

The state variable format is: `Step|Username|Password|Result`

1.  **Step 1**: Run `1_CreateTempAdmin.ps1`. Store result in `%WingetState%`.
2.  **Step 2**: Run `2_AddLocalAdmin.ps1 -State "%WingetState%"`. Update `%WingetState%` with the result.
3.  **Step 3**: Run `3_GrantLogonAsBatch.ps1 -State "%WingetState%"`. Update `%WingetState%` with the result.
4.  **Step 4**: Run `4_EnableAccount.ps1 -State "%WingetState%"`. Update `%WingetState%` with the result.
5.  **Step 5**: Run `5_RunWingetUpdate.ps1 -State "%WingetState%"`. Update `%WingetState%` with the result. (Run as Admin).
6.  **Step 6**: Run `6_RemoveTempAdmin.ps1 -State "%WingetState%"`.

## Scripts

- **1_CreateTempAdmin.ps1**: Outputs `1|Username|Password|UserCreated`.
- **2_AddLocalAdmin.ps1**: Outputs `2|Username|Password|AddedToAdmin`.
- **3_GrantLogonAsBatch.ps1**: Outputs `3|Username|Password|BatchLogonGranted`.
- **4_EnableAccount.ps1**: Outputs `4|Username|Password|AccountEnabled`.
- **5_RunWingetUpdate.ps1**: Outputs `5|Username|Password|WingetUpdated`.
- **6_RemoveTempAdmin.ps1**: Outputs `6|Username|Password|UserRemoved`.

## Technical Specs

- **PowerShell 5.1** compatible.
- Encapsulated string interpolation `${VarName}` for parser safety.
- Handles standard user/password sanitation for Windows Task Scheduler.
