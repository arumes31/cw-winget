param(
    [Parameter(Mandatory = $true)]
    [hashtable]$State
)

$Username = $State.Username

try {
    Add-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction Stop
}
catch {
    $State.Error = "Failed to add $Username to Administrators: $($_.Exception.Message)"
}

return $State
