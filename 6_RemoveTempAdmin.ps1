param(
    [Parameter(Mandatory = $true)]
    [string]$Username
)

try {
    Remove-LocalUser -Name $Username -ErrorAction Stop
    Write-Host "Successfully removed temporary admin user: $Username"
}
catch {
    Write-Error "Failed to remove user $Username: $($_.Exception.Message)"
    exit 1
}
