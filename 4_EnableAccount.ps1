param(
    [Parameter(Mandatory = $true)]
    [string]$State
)

# 4_EnableAccount.ps1 - ConnectWise Automate compatible
# Input: Username|Password
# Output: Username|Password

$Parts = $State.Split('|')
if ($Parts.Count -lt 1) {
    Write-Error "Invalid state string: $State"
    exit 1
}
$Username = $Parts[0].Trim()

try {
    Enable-LocalUser -Name $Username -ErrorAction Stop
    Write-Output $State
}
catch {
    Write-Error "Failed to enable account $Username: $($_.Exception.Message)"
    exit 1
}
