param(
    [Parameter(Mandatory = $true)]
    [hashtable]$State
)

$Username = $State.Username

try {
    Enable-LocalUser -Name $Username -ErrorAction Stop
}
catch {
    $State.Error = "Failed to enable account $Username: $($_.Exception.Message)"
}

return $State
