param(
    [Parameter(Mandatory=$true)]
    [string]$Username
)

$TmpFile = Join-Path $env:TEMP "secedit_export.inf"
$CfgFile = Join-Path $env:TEMP "secedit_import.inf"

try {
    # Export current security policy
    secedit /export /cfg $TmpFile /areas USER_RIGHTS | Out-Null

    $Content = Get-Content $TmpFile
    $BatchLogonLine = $Content | Where-Object { $_ -like "*SeBatchLogonRight*" }

    if ($BatchLogonLine) {
        if ($BatchLogonLine -notlike "*$Username*") {
            $NewBatchLogonLine = "$BatchLogonLine,$Username"
            $Content = $Content -replace [regex]::Escape($BatchLogonLine), $NewBatchLogonLine
        } else {
            Write-Host "User $Username already has SeBatchLogonRight."
            return
        }
    } else {
        $Content += "SeBatchLogonRight = $Username"
    }

    $Content | Set-Content $CfgFile

    # Import modified security policy
    secedit /configure /db $env:windir\security\local.sdb /cfg $CfgFile /areas USER_RIGHTS | Out-Null
    
    # Force policy refresh
    gpupdate /force | Out-Null

    Write-Host "Successfully granted SeBatchLogonRight to $Username."
} catch {
    Write-Error "Failed to grant SeBatchLogonRight: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path $TmpFile) { Remove-Item $TmpFile }
    if (Test-Path $CfgFile) { Remove-Item $CfgFile }
}
