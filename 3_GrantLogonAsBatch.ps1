param(
    [Parameter(Mandatory = $true)]
    [hashtable]$State
)

$Username = $State.Username

if (-not (Get-Module -ListAvailable Microsoft.PowerShell.LocalAccounts)) {
    $State.Error = "Microsoft.PowerShell.LocalAccounts module required."
    return $State
}

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
            return $State
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
}
catch {
    $State.Error = "Failed to grant SeBatchLogonRight: $($_.Exception.Message)"
}
finally {
    if (Test-Path $TmpFile) { Remove-Item $TmpFile }
    if (Test-Path $CfgFile) { Remove-Item $CfgFile }
}

return $State
