# 6_DisableTempAdmin.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result

$State = @'
@state@
'@.Trim()

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()
$Password = $Parts[2].Trim()

try {
    $User = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $User) {
        Write-Output "6|${Username}|${Password}|UserNotFound"
        return
    }

    if (-not $User.Enabled) {
        Write-Output "6|${Username}|${Password}|AlreadyDisabled"
        return
    }

    Disable-LocalUser -Name $Username -ErrorAction Stop
    Write-Output "6|${Username}|${Password}|UserDisabled"
}
catch {
    Write-Error "Failed to disable user ${Username}: $($_.Exception.Message)"
    exit 1
}
