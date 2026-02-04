# Winget Automated Update Utility

This utility allows running `winget` updates from a non-interactive context (like the SYSTEM account) by creating a temporary local administrator.

## Scripts

1.  **[1_CreateTempAdmin.ps1](file:///c:/DR/Nextcloud/BUILD/cw-winget/1_CreateTempAdmin.ps1)**: Creates a temporary user with a random password and outputs `username|password`.
2.  **[2_AddLocalAdmin.ps1](file:///c:/DR/Nextcloud/BUILD/cw-winget/2_AddLocalAdmin.ps1)**: Adds the user to the local Administrators group.
3.  **[3_GrantLogonAsBatch.ps1](file:///c:/DR/Nextcloud/BUILD/cw-winget/3_GrantLogonAsBatch.ps1)**: Grants "Logon as batch job" permission using `secedit`.
4.  **[4_EnableAccount.ps1](file:///c:/DR/Nextcloud/BUILD/cw-winget/4_EnableAccount.ps1)**: Ensures the account is enabled.
5.  **[5_RunWingetUpdate.ps1](file:///c:/DR/Nextcloud/BUILD/cw-winget/5_RunWingetUpdate.ps1)**: Runs `winget upgrade --all` via a temporary scheduled task.
6.  **[6_RemoveTempAdmin.ps1](file:///c:/DR/Nextcloud/BUILD/cw-winget/6_RemoveTempAdmin.ps1)**: Cleanup the temporary user.

## Master Script

**[Run-WingetAutomated.ps1](file:///c:/DR/Nextcloud/BUILD/cw-winget/Run-WingetAutomated.ps1)**

This script orchestrates the entire process. It captures the credentials from step 1 and passes them through steps 2-5, finally cleaning up in step 6.

### Usage

Run from an elevated PowerShell prompt:
```powershell
.\Run-WingetAutomated.ps1
```

Or run via Task Scheduler as SYSTEM.
