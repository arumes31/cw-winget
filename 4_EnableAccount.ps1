param(
    [Parameter(Mandatory = $true)]
    [string]$State
)

# 4_EnableAccount.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string: ${State}. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()
$Password = $Parts[2].Trim()

try {
    Enable-LocalUser -Name $Username -ErrorAction Stop
    Write-Output "4|${Username}|${Password}|AccountEnabled"
}
catch {
    Write-Error "Failed to enable account ${Username}: $($_.Exception.Message)"
    exit 1
}
