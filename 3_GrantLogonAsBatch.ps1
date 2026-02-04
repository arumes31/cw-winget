param(
    [Parameter(Mandatory = $true)]
    [string]$State
)

# 3_GrantLogonAsBatch.ps1 - ConnectWise Automate compatible
# Input: Username|Password
# Output: Username|Password

$Parts = $State.Split('|')
if ($Parts.Count -lt 1) {
    Write-Error "Invalid state string: $State"
    exit 1
}
$Username = $Parts[0].Trim()

$TmpFile = Join-Path $env:TEMP "secedit_export.inf"
$CfgFile = Join-Path $env:TEMP "secedit_import.inf"

try {
    secedit /export /cfg $TmpFile /areas USER_RIGHTS | Out-Null
    $Content = Get-Content $TmpFile -Encoding Unicode
    $BatchLogonLine = $Content | Where-Object { $_ -like "*SeBatchLogonRight*" }

    if ($BatchLogonLine) {
        if ($BatchLogonLine -notlike "*$Username*") {
            $NewBatchLogonLine = "$BatchLogonLine,$Username"
            $Content = $Content -replace [regex]::Escape($BatchLogonLine), $NewBatchLogonLine
        }
        else {
            Write-Output $State
            return
        }
    }
    else {
        $PrivIndex = $Content.IndexOf("[Privilege Rights]")
        if ($PrivIndex -ge 0) {
            $Content = $Content[0..$PrivIndex] + "SeBatchLogonRight = $Username" + $Content[($PrivIndex + 1)..$Content.Length]
        }
        else {
            $Content += "[Privilege Rights]"
            $Content += "SeBatchLogonRight = $Username"
        }
    }

    $Content | Set-Content $CfgFile -Encoding Unicode
    secedit /configure /db $env:windir\security\local.sdb /cfg $CfgFile /areas USER_RIGHTS | Out-Null
    gpupdate /force | Out-Null
    
    Write-Output $State
}
catch {
    Write-Error "Failed to grant SeBatchLogonRight: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path $TmpFile) { Remove-Item $TmpFile }
    if (Test-Path $CfgFile) { Remove-Item $CfgFile }
}
