# 6_DisableTempAdmin.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result

$State = "@state@"

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string: ${State}. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()
$Password = $Parts[2].Trim()

try {
    Write-Host "Disabling temporary admin user: ${Username}..."
    Disable-LocalUser -Name $Username -ErrorAction Stop
    Write-Output "6|${Username}|${Password}|UserDisabled"
}
catch {
    Write-Error "Failed to disable user ${Username}: $($_.Exception.Message)"
    exit 1
}
