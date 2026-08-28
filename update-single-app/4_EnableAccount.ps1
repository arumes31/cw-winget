# 4_EnableAccount.ps1 - retained for ConnectWise Automate workflow compatibility.
# Input/Output: Step|Username|Result
# The account is deliberately kept disabled until step 5 has an in-memory credential.

$State = '@state@'
$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string. Expected Step|Username|Result"
    exit 1
}
$Username = $Parts[1].Trim()

try {
    try {
        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        if ($User.Enabled) {
            Disable-LocalUser -Name $Username -ErrorAction Stop
        }
    }
    catch {
        $User = [ADSI]"WinNT://$env:COMPUTERNAME/$Username,user"
        if ($null -eq $User.Name) { throw "User not found" }
        $UserFlags = $User.Value("UserFlags")
        if (($UserFlags -band 2) -ne 2) {
            $User.Put("UserFlags", ($UserFlags -bor 2))
            $User.SetInfo()
        }
    }
    Write-Output "4|${Username}|AccountPreparedDisabled"
}
catch {
    Write-Error "Failed to prepare account ${Username}: $($_.Exception.Message)"
    exit 1
}
