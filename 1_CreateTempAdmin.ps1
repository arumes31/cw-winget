param(
    [string]$State = ""
)

# 1_CreateTempAdmin.ps1 - ConnectWise Automate compatible
# Outputs: Step|Username|Password|Result

if (-not (Get-Module -ListAvailable Microsoft.PowerShell.LocalAccounts)) {
    Write-Error "Microsoft.PowerShell.LocalAccounts module required."
    exit 1
}

$Username = "TempAutomateAdmin"

$PasswordLength = 16
$CharacterSets = @(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "01234456789"
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
    
    $ExistingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($ExistingUser) {
        Write-Host "User ${Username} already exists. Updating password..."
        Set-LocalUser -Name $Username -Password $SecurePassword -ErrorAction Stop
        $Result = "PasswordUpdated"
    }
    else {
        Write-Host "Creating new user ${Username}..."
        New-LocalUser -Name $Username -Password $SecurePassword -Description "Temporary Automation Admin" -FullName "Temp Automate Admin" -ErrorAction Stop | Out-Null
        $Result = "UserCreated"
    }
    
    # Final Output: Step|Username|Password|Result
    Write-Output "1|${Username}|${Password}|${Result}"
}
catch {
    Write-Error "Failed to manage user ${Username}: $($_.Exception.Message)"
    exit 1
}
