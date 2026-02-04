param(
    [Parameter(Mandatory = $true)]
    [hashtable]$State
)

$Username = $State.Username

try {
    Remove-LocalUser -Name $Username -ErrorAction Stop
}
catch {
    $State.Error = "Failed to remove user $Username: $($_.Exception.Message)"
}

return $State
