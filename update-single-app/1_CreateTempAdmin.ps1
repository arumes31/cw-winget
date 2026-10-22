param(
    [string]$State = ""
)

# 1_CreateTempAdmin.ps1 - ConnectWise Automate compatible
# Outputs: Step|Username|Password|Result
# The Password field is always "Redacted": the real password never leaves this machine.
# 5_RunWingetUpdate.ps1 sets a fresh password in-process right before it registers the task.

# Load module silently
Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue

$UserPrefix = "TempWinget_"
$UserDescription = "Temporary Automation Admin"
$Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

# Unbiased random integer in [0, Maximum) from the cryptographic RNG (rejection sampling)
function Get-SecureRandomInt {
    param([int]$Maximum)
    $Bytes = New-Object byte[] 4
    $Limit = [uint32]::MaxValue - ([uint32]::MaxValue % $Maximum)
    do {
        $Rng.GetBytes($Bytes)
        $Value = [BitConverter]::ToUInt32($Bytes, 0)
    } while ($Value -ge $Limit)
    return [int]($Value % $Maximum)
}

function New-RandomString {
    param([string]$Chars, [int]$Length)
    $Result = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $Result += $Chars[(Get-SecureRandomInt $Chars.Length)]
    }
    return $Result
}

function New-RandomPassword {
    param([int]$Length = 24)
    $CharacterSets = @(
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        'abcdefghijklmnopqrstuvwxyz'
        '0123456789'
        '!@#$%^&*()_+'
    )
    $PasswordArray = @()
    foreach ($set in $CharacterSets) {
        $PasswordArray += $set[(Get-SecureRandomInt $set.Length)]
    }
    $AllChars = ($CharacterSets -join "")
    for ($i = $CharacterSets.Count; $i -lt $Length; $i++) {
        $PasswordArray += $AllChars[(Get-SecureRandomInt $AllChars.Length)]
    }
    # Fisher-Yates shuffle
    for ($i = $PasswordArray.Count - 1; $i -gt 0; $i--) {
        $j = Get-SecureRandomInt ($i + 1)
        $temp = $PasswordArray[$i]
        $PasswordArray[$i] = $PasswordArray[$j]
        $PasswordArray[$j] = $temp
    }
    return -join $PasswordArray
}

# Remove leftover temp admins from earlier runs that never reached step 6 (only disabled ones,
# so a run that is still in progress is never touched). Includes the legacy fixed-name account.
try {
    Get-LocalUser -ErrorAction Stop | Where-Object {
        ($_.Name -like "$UserPrefix*" -or $_.Name -eq "TempAutomateAdmin") -and
        $_.Description -eq $UserDescription -and -not $_.Enabled
    } | ForEach-Object {
        $StaleSid = $_.SID.Value
        Remove-LocalUser -SID $_.SID -ErrorAction SilentlyContinue
        Get-CimInstance Win32_UserProfile -Filter "SID = '$StaleSid'" -ErrorAction SilentlyContinue | Remove-CimInstance -ErrorAction SilentlyContinue
    }
}
catch {}

# Per-run random username (max 20 chars for local accounts)
$Username = $UserPrefix + (New-RandomString "abcdefghijklmnopqrstuvwxyz0123456789" 8)
$Password = New-RandomPassword 24

try {
    $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $Result = $null

    # Tier 1: Modern PowerShell local user cmdlets
    # The account is created disabled; 4_EnableAccount.ps1 enables it only for the update window.
    try {
        $ExistingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if ($ExistingUser) {
            Set-LocalUser -Name $Username -Password $SecurePassword -ErrorAction Stop
            $Result = "PasswordUpdated"
        }
        else {
            New-LocalUser -Name $Username -Password $SecurePassword -Description $UserDescription -FullName "Temp Automate Admin" -Disabled -ErrorAction Stop | Out-Null
            $Result = "UserCreated"
        }
    }
    catch {
        # Tier 2: Native ADSI (Active Directory Service Interfaces) WinNT provider fallback
        try {
            $Computer = [ADSI]"WinNT://$env:COMPUTERNAME"
            $UserExists = $false
            try {
                $User = [ADSI]"WinNT://$env:COMPUTERNAME/$Username,user"
                if ($User.Name -ne $null) { $UserExists = $true }
            } catch {
                $UserExists = $false
            }

            if ($UserExists) {
                $User.SetPassword($Password)
                $User.SetInfo()
                $Result = "PasswordUpdated"
            }
            else {
                $NewUser = $Computer.Create("user", $Username)
                $NewUser.SetPassword($Password)
                $NewUser.Put("Description", $UserDescription)
                $NewUser.Put("FullName", "Temp Automate Admin")
                # ADS_UF_ACCOUNTDISABLE (2) | ADS_UF_NORMAL_ACCOUNT (512)
                $NewUser.Put("UserFlags", 514)
                $NewUser.SetInfo()
                $Result = "UserCreated"
            }
        }
        catch {
            # Tier 3: Legacy command-line net user fallback
            try {
                net user $Username > $null 2>&1
                if ($LASTEXITCODE -eq 0) {
                    # User exists, update password
                    $Proc = Start-Process net.exe -ArgumentList "user `"$Username`" `"$Password`"" -NoNewWindow -PassThru -Wait
                    if ($Proc.ExitCode -ne 0) { throw "net user password update failed" }
                    $Result = "PasswordUpdated"
                }
                else {
                    # User does not exist, create (disabled)
                    $Proc = Start-Process net.exe -ArgumentList "user `"$Username`" `"$Password`" /add /active:no /comment:`"$UserDescription`" /y" -NoNewWindow -PassThru -Wait
                    if ($Proc.ExitCode -ne 0) { throw "net user add failed" }
                    $Result = "UserCreated"
                }
            }
            catch {
                throw "Failed to manage user ${Username} via local accounts, ADSI, or net user: $($_.Exception.Message)"
            }
        }
    }

    # Final Output: Step|Username|Password|Result
    # Strictly one line of output for state capture. The password is never emitted.
    Write-Output "1|${Username}|Redacted|${Result}"
}
catch {
    Write-Error "Failed to manage user ${Username}: $($_.Exception.Message)"
    exit 1
}
finally {
    $Rng.Dispose()
}
