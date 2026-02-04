param(
    [Parameter(Mandatory = $true)]
    [hashtable]$State
)

if (-not (Get-Module -ListAvailable Microsoft.PowerShell.LocalAccounts)) {
    $State.Error = "Microsoft.PowerShell.LocalAccounts module required."
    return $State
}

$Username = $State.Username
$ExistingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
if ($ExistingUser) {
    $State.Error = "User $Username already exists."
    return $State
}

$PasswordLength = 16
$CharacterSets = @(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "0123456789"
    "!@#$%^&*()_+"
)

$Password = ""
foreach ($set in $CharacterSets) {
    $Password += $set[(Get-Random -Maximum $set.Length)]
}

$AllChars = ($CharacterSets -join "")
for ($i = 4; $i -lt $PasswordLength; $i++) {
    $Password += $AllChars[(Get-Random -Maximum $AllChars.Length)]
}

# Shuffle
$PasswordArray = $Password.ToCharArray()
for ($i = $PasswordArray.Length - 1; $i -gt 0; $i--) {
    $j = Get-Random -Maximum ($i + 1)
    $temp = $PasswordArray[$i]
    $PasswordArray[$i] = $PasswordArray[$j]
    $PasswordArray[$j] = $temp
}
$Password = -join $PasswordArray

try {
    $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Username -Password $SecurePassword -Description "Temporary Automation Admin" -FullName "Temp Automate Admin" | Out-Null
    
    $State.Password = $Password
}
catch {
    $State.Error = "Failed to create user: $($_.Exception.Message)"
}

return $State
