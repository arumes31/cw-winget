param(
    [Parameter(Mandatory = $true)]
    [string]$State
)

# 2_AddLocalAdmin.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string: ${State}. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()
$Password = $Parts[2].Trim()

try {
    Add-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction Stop
    # Return updated state: Step|Username|Password|Result
    Write-Output "2|${Username}|${Password}|AddedToAdmin"
}
catch {
    Write-Error "Failed to add ${Username} to Administrators: $($_.Exception.Message)"
    exit 1
}
