param(
    [Parameter(Mandatory = $true)]
    [string]$State
)

# 2_AddLocalAdmin.ps1 - ConnectWise Automate compatible
# Input: Username|Password
# Output: Username|Password

$Parts = $State.Split('|')
if ($Parts.Count -lt 1) {
    Write-Error "Invalid state string: $State"
    exit 1
}
$Username = $Parts[0].Trim()

try {
    Add-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction Stop
    # Return the state for the next step
    Write-Output $State
}
catch {
    Write-Error "Failed to add $Username to Administrators: $($_.Exception.Message)"
    exit 1
}
