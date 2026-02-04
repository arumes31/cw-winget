# 4_EnableAccount.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result

$State = '@state@'

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
        Write-Error "User ${Username} not found."
        exit 1
    }
    
    if ($User.Enabled) {
        Write-Output "4|${Username}|${Password}|AlreadyEnabled"
        return
    }

    Enable-LocalUser -Name $Username -ErrorAction Stop
    Write-Output "4|${Username}|${Password}|AccountEnabled"
}
catch {
    Write-Error "Failed to enable account ${Username}: $($_.Exception.Message)"
    exit 1
}
