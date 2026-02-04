# Winget Automated Update Utility - Update All (ConnectWise Automate)

This utility is designed for ConnectWise Automate workflows. It uses a single variable to pass state between steps via `@state@` placeholder injection.

## ConnectWise Automate Integration

The state variable format is: `Step|Username|Password|Result[|WingetLog]`

1.  **Step 1**: Run `1_CreateTempAdmin.ps1`. Store result in `%WingetState%`.
2.  **Step 2**: Run `2_AddLocalAdmin.ps1`. Before running, Automate replaces `@state@` with `%WingetState%`. Store result back in `%WingetState%`.
3.  **Step 3**: Run `3_GrantLogonAsBatch.ps1`. Store result in `%WingetState%`.
4.  **Step 4**: Run `4_EnableAccount.ps1`. Store result in `%WingetState%`.
5.  **Step 5**: Run `5_RunWingetUpdate.ps1` (Run as Admin). Outputs logs in the state. Store result in `%WingetState%`.
6.  **Step 6**: Run `6_DisableTempAdmin.ps1`.

## Scripts

- **1_CreateTempAdmin.ps1**: Outputs state, updates password if user exists.
- **2_AddLocalAdmin.ps1**: Uses `@state@`, adds user to local admins.
- **3_GrantLogonAsBatch.ps1**: Uses `@state@`, grants 'Logon as batch job'.
- **4_EnableAccount.ps1**: Uses `@state@`, enables the account.
- **5_RunWingetUpdate.ps1**: Uses `@state@`, runs upgrades. Outputs: `5|User|Pass|WingetUpdated|LogData`.
- **6_DisableTempAdmin.ps1**: Uses `@state@`, disables the account.

## Technical Details

- **Placeholder Injection**: Scripts 2-6 use `$State = "@state@"` for CW Automate compatibility.
- **Robustness**: Step 5 captures up to 1000 characters of the Winget log, cleaned for state-string compatibility (newlines replaced with `;`, pipes replaced with `/`).
- **PowerShell 5.1** compatible.
- **Idempotency**: All scripts are safe to run multiple times.
