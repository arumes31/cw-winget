param(
    [Parameter(Mandatory=$true)]
    [string]$Username
)

try {
    Add-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction Stop
    Write-Host "Successfully added $Username to Administrators group."
} catch {
    Write-Error "Failed to add $Username to Administrators group: $($_.Exception.Message)"
    exit 1
}
