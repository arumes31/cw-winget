# 2_AddLocalAdmin.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result

$State = '@state@'

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()
$Password = $Parts[2].Trim()

try {
    $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $AdminGroup = $AdminSid.Translate([System.Security.Principal.NTAccount]).Value

    $currentMembers = Get-LocalGroupMember -Group $AdminGroup -ErrorAction SilentlyContinue
    if ($currentMembers -and ($currentMembers.Name -contains "${Username}" -or $currentMembers.Name -contains "$env:COMPUTERNAME\${Username}")) {
        Write-Output "2|${Username}|${Password}|AlreadyAdmin"
        return
    }
    Add-LocalGroupMember -Group $AdminGroup -Member $Username -ErrorAction Stop
    Write-Output "2|${Username}|${Password}|AddedToAdmin"
}
catch {
    $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $AdminGroup = $AdminSid.Translate([System.Security.Principal.NTAccount]).Value
    Write-Error "Failed to add ${Username} to $($AdminGroup): $($_.Exception.Message)"
    exit 1
}
