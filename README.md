# <img width="500" height="500" alt="project_logo_transparent-removebg-preview" src="https://github.com/user-attachments/assets/1be9cc33-7c04-4204-bfe9-cc2cc159c0ee" /> 
# ConnectWise Automate Winget Wrapper

This project provides PowerShell scripts to integrate `winget` (Windows Package Manager) with ConnectWise Automate (CWA). It allows for automated application updates and installations running as a temporary administrative user, bypassing system context limitations.

## Project Structure

The project is divided into two main workflows:

1.  **[update-all](./update-all/)**: Upgrades **all** installed packages on the system.
2.  **[update-single-app](./update-single-app/)**: Checks for and installs/updates a **single specific application**.

## Workflows

### 1. Update All
located in `./update-all/`

This workflow attempts to run `winget upgrade --all` to update all packages available in the configured sources.

**Usage:**
- Designed to be run as a sequence of scripts in ConnectWise Automate.
- Uses `@state@` variable replacement to maintain state (username/password/logs) between script steps.

### 2. Update Single App
located in `./update-single-app/`

This workflow manages a specific application defined by the `@installapp@` variable.

**Usage:**
- **Variable Injection**: requires `@installapp@` to be replaced by the ID of the application (e.g., `Google.Chrome`) by the CWA script engine.
- **Logic**:
    - Checks if the application is available via `winget search`.
    - If found, runs `winget install --id <AppId> --exact --force`.
    - This command handles both fresh installations and updates to existing installations.

## ConnectWise Automate Integration

Both workflows share the same state-passing mechanism:

**State Format:** `Step|Username|Password|Result[|WingetLog]`

### Script Sequence:
1.  **1_CreateTempAdmin.ps1**: Creates a temporary local admin account.
2.  **2_AddLocalAdmin.ps1**: Adds the temp user to the Administrators group.
3.  **3_GrantLogonAsBatch.ps1**: Grants 'Logon as batch job' rights.
4.  **4_EnableAccount.ps1**: Enables the account.
5.  **5_RunWingetUpdate.ps1** (Run as Admin):
    - **Update-All**: upgrades everything.
    - **Update-Single-App**: installs/updates the specific target.
6.  **6_DisableTempAdmin.ps1**: Disables the temp account and cleans up.

## Requirements
- Windows 10/11 or Server 2019+ (with App Installer/Winget support).
- PowerShell 5.1.

## Multi-Language & Non-English OS Support

These scripts are specifically optimized to support non-English Windows environments (e.g., German, Spanish, French OS):
- **Local Administrators SID-Based Translation**: Dynamic group name resolution via well-known SID `S-1-5-32-544` to seamlessly resolve local groups such as `Administratoren`, `Administradores`, or `Administrateurs`.
- **Robust Membership Matching**: Split-prefix and wildcard matching on `Domain\Username` formats to avoid false negatives when checking if a user is already a local administrator.
- **Dynamic Membership Catch Fallback**: Caught exceptions in group membership addition are verified dynamically against active group rosters to eliminate localized error string parsing failures.
- **Safe-ASCII Log Whitelisting**: Safe ASCII-only sanitization (`[^a-zA-Z0-9\.\,\-\_\:\/\(\)\[\]\+\s]`) to wipe out localization garbage characters (e.g. `RedistributÇ½ƒ'ª`) and avoid premature CWA string preprocessor single-quote truncation parser errors.

## Disclaimer

This project is not affiliated with, endorsed by, or sponsored by ConnectWise. ConnectWise Automate® is a registered trademark of ConnectWise, LLC. These scripts are provided "as is" without warranty of any kind. Use at your own risk.
