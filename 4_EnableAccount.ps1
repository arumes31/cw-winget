param(
    [Parameter(Mandatory=$true)]
    [string]$Username
)

try {
    Enable-LocalUser -Name $Username -ErrorAction Stop
    Write-Host "Successfully enabled account: $Username"
} catch {
    Write-Error "Failed to enable account $Username: $($_.Exception.Message)"
    exit 1
}
