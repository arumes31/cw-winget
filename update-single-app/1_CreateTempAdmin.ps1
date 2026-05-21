param(
    [string]$State = ""
)

# 1_CreateTempAdmin.ps1 - ConnectWise Automate compatible
# Outputs: Step|Username|Password|Result

# Load module silently
Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue

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
    $Result = $null
    
    # Tier 1: Modern PowerShell local user cmdlets
    try {
        $ExistingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if ($ExistingUser) {
            Set-LocalUser -Name $Username -Password $SecurePassword -ErrorAction Stop
            $Result = "PasswordUpdated"
        }
        else {
            New-LocalUser -Name $Username -Password $SecurePassword -Description "Temporary Automation Admin" -FullName "Temp Automate Admin" -ErrorAction Stop | Out-Null
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
                $NewUser.Put("Description", "Temporary Automation Admin")
                $NewUser.Put("FullName", "Temp Automate Admin")
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
                    # User does not exist, create
                    $Proc = Start-Process net.exe -ArgumentList "user `"$Username`" `"$Password`" /add /y" -NoNewWindow -PassThru -Wait
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
    # Strictly one line of output for state capture
    Write-Output "1|${Username}|${Password}|${Result}"
}
catch {
    Write-Error "Failed to manage user ${Username}: $($_.Exception.Message)"
    exit 1
}
