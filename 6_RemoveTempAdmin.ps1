param(
    [Parameter(Mandatory = $true)]
    [string]$State
)

# 6_RemoveTempAdmin.ps1 - ConnectWise Automate compatible
# Input: Username|Password
# Output: Done

$Parts = $State.Split('|')
if ($Parts.Count -lt 1) {
    Write-Error "Invalid state string: ${State}"
    exit 1
}
$Username = $Parts[0].Trim()

try {
    Remove-LocalUser -Name $Username -ErrorAction Stop
    Write-Output "Done"
}
catch {
    Write-Error "Failed to remove user ${Username}: $($_.Exception.Message)"
    exit 1
}
