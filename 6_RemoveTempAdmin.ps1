param(
    [Parameter(Mandatory = $true)]
    [string]$State
)

# 6_RemoveTempAdmin.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string: ${State}. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()
$Password = $Parts[2].Trim()

try {
    Remove-LocalUser -Name $Username -ErrorAction Stop
    Write-Output "6|${Username}|${Password}|UserRemoved"
}
catch {
    Write-Error "Failed to remove user ${Username}: $($_.Exception.Message)"
    exit 1
}
