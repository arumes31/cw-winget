# 1_CreateTempAdmin.ps1 - ConnectWise Automate compatible
# Output: Step|Username|Result. Credentials never leave this process.

# Load module silently
Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue

$Username = "TempAutomateAdmin"

$PasswordLength = 32
$CharacterSets = @(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "0123456789"
    "!@#$%^&*_-+="
)

function Get-CryptographicIndex {
    param([Parameter(Mandatory)][int]$UpperBound)

    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object byte[] 1
        $limit = 256 - (256 % $UpperBound)
        do {
            $generator.GetBytes($bytes)
            $value = [int]$bytes[0]
        } while ($value -ge $limit)
        return $value % $UpperBound
    }
    finally {
        $generator.Dispose()
    }
}

function New-CryptographicPassword {
    $characters = New-Object System.Collections.Generic.List[char]
    foreach ($set in $CharacterSets) {
        [void]$characters.Add($set[(Get-CryptographicIndex -UpperBound $set.Length)])
    }
    $allCharacters = $CharacterSets -join ""
    while ($characters.Count -lt $PasswordLength) {
        [void]$characters.Add($allCharacters[(Get-CryptographicIndex -UpperBound $allCharacters.Length)])
    }
    for ($i = $characters.Count - 1; $i -gt 0; $i--) {
        $j = Get-CryptographicIndex -UpperBound ($i + 1)
        $temporary = $characters[$i]
        $characters[$i] = $characters[$j]
        $characters[$j] = $temporary
    }
    return -join $characters
}

$Password = New-CryptographicPassword

try {
    $SecurePassword = New-Object System.Security.SecureString
    foreach ($character in $Password.ToCharArray()) { $SecurePassword.AppendChar($character) }
    $SecurePassword.MakeReadOnly()
    $Result = $null
    
    # Tier 1: Modern PowerShell local user cmdlets
    try {
        $ExistingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if ($ExistingUser) {
            if ($ExistingUser.Enabled) { Disable-LocalUser -Name $Username -ErrorAction Stop }
            Set-LocalUser -Name $Username -Password $SecurePassword -ErrorAction Stop
            $Result = "PasswordUpdated"
        }
        else {
            New-LocalUser -Name $Username -Password $SecurePassword -Description "Temporary Automation Admin" -FullName "Temp Automate Admin" -Disabled -ErrorAction Stop | Out-Null
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
                $UserFlags = $User.Value("UserFlags")
                $User.Put("UserFlags", ($UserFlags -bor 2))
                $User.SetInfo()
                $User.SetPassword($Password)
                $User.SetInfo()
                $Result = "PasswordUpdated"
            }
            else {
                $NewUser = $Computer.Create("user", $Username)
                $NewUser.SetPassword($Password)
                $NewUser.Put("Description", "Temporary Automation Admin")
                $NewUser.Put("FullName", "Temp Automate Admin")
                $NewUser.Put("UserFlags", 2)
                $NewUser.SetInfo()
                $Result = "UserCreated"
            }
        }
        catch {
            throw "Failed to manage user ${Username} without exposing its credential: $($_.Exception.Message)"
        }
    }

    # Keep the account unusable between independently executed CWA steps.
    try {
        Disable-LocalUser -Name $Username -ErrorAction Stop
    }
    catch {
        $User = [ADSI]"WinNT://$env:COMPUTERNAME/$Username,user"
        $UserFlags = $User.Value("UserFlags")
        $User.Put("UserFlags", ($UserFlags -bor 2))
        $User.SetInfo()
    }

    $SecurePassword.Dispose()
    $Password = $null
    Write-Output "1|${Username}|${Result}"
}
catch {
    Write-Error "Failed to manage user ${Username}: $($_.Exception.Message)"
    exit 1
}
