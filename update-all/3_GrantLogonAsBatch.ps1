# 3_GrantLogonAsBatch.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result

$State = '@state@'

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string. Expected Step|Username|Password|Result"
    exit 1
}
$Username = $Parts[1].Trim()
$Password = $Parts[2].Trim()

# Only ever operate on the per-run account created by 1_CreateTempAdmin.ps1
if ($Username -notmatch "^TempWinget_[a-z0-9]{8}$") {
    Write-Error "Refusing to operate on unexpected account name: $Username"
    exit 1
}

# Creates a uniquely named working directory that only SYSTEM and Administrators (plus the optional
# accounts in $ModifyAccounts) can access. The protected ACL is applied atomically at creation time,
# so standard users can neither pre-create the folder nor tamper with files placed in it.
function New-ProtectedWorkDir {
    param([string[]]$ModifyAccounts = @())

    $BaseDir = Join-Path $env:windir "LTSvc"
    if (-not (Test-Path $BaseDir)) { $BaseDir = $env:ProgramData }
    $Path = Join-Path $BaseDir ("WingetWork_" + [guid]::NewGuid().ToString("N"))
    if (Test-Path -LiteralPath $Path) { throw "Working directory $Path already exists" }

    $SystemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $Inherit = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
    $Propagate = [System.Security.AccessControl.PropagationFlags]::None
    $Security = New-Object System.Security.AccessControl.DirectorySecurity
    $Security.SetAccessRuleProtection($true, $false)
    $Security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, "FullControl", $Inherit, $Propagate, "Allow")))
    $Security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($AdminSid, "FullControl", $Inherit, $Propagate, "Allow")))
    foreach ($Account in $ModifyAccounts) {
        $AccountSid = (New-Object System.Security.Principal.NTAccount($Account)).Translate([System.Security.Principal.SecurityIdentifier])
        $Security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($AccountSid, "Modify", $Inherit, $Propagate, "Allow")))
    }

    if ($PSVersionTable.PSEdition -eq "Core") {
        [void][System.IO.FileSystemAclExtensions]::Create((New-Object System.IO.DirectoryInfo($Path)), $Security)
    }
    else {
        [void][System.IO.Directory]::CreateDirectory($Path, $Security)
    }

    # Defense in depth: fail closed if the folder is not ours or is not empty
    $Owner = (Get-Acl -LiteralPath $Path).GetOwner([System.Security.Principal.SecurityIdentifier])
    $CurrentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    if (-not ($Owner.Equals($SystemSid) -or $Owner.Equals($AdminSid) -or $Owner.Equals($CurrentSid))) { throw "Working directory $Path has unexpected owner $Owner" }
    if (Get-ChildItem -LiteralPath $Path -Force) { throw "Working directory $Path is not empty" }
    return $Path
}

# secedit files live in a SYSTEM/Administrators-only folder instead of the world-writable
# SYSTEM TEMP (C:\Windows\Temp), so other users cannot race or edit the policy template.
$SeceditDir = $null

try {
    $SeceditDir = New-ProtectedWorkDir
    $TmpFile = Join-Path $SeceditDir "secedit_export.inf"
    $CfgFile = Join-Path $SeceditDir "secedit_import.inf"

    secedit /export /cfg $TmpFile /areas USER_RIGHTS | Out-Null
    $Content = Get-Content $TmpFile -Encoding Unicode
    $BatchLogonLine = $Content | Where-Object { $_ -like "*SeBatchLogonRight*" }

    $IsAlreadyGranted = $false
    if ($BatchLogonLine) {
        if ($BatchLogonLine -like "*$Username*") {
            $IsAlreadyGranted = $true
        }
    }

    if ($IsAlreadyGranted) {
        Write-Output "3|${Username}|${Password}|BatchLogonExists"
        return
    }

    if ($BatchLogonLine) {
        $NewBatchLogonLine = "$BatchLogonLine,$Username"
        $Content = $Content -replace [regex]::Escape($BatchLogonLine), $NewBatchLogonLine
    }
    else {
        $PrivIndex = $Content.IndexOf("[Privilege Rights]")
        if ($PrivIndex -ge 0) {
            $Content = $Content[0..$PrivIndex] + "SeBatchLogonRight = ${Username}" + $Content[($PrivIndex + 1)..$Content.Length]
        }
        else {
            $Content += "[Privilege Rights]"
            $Content += "SeBatchLogonRight = ${Username}"
        }
    }

    $Content | Set-Content $CfgFile -Encoding Unicode
    secedit /configure /db $env:windir\security\local.sdb /cfg $CfgFile /areas USER_RIGHTS | Out-Null
    gpupdate /force | Out-Null
    
    Write-Output "3|${Username}|${Password}|BatchLogonGranted"
}
catch {
    Write-Error "Failed to grant SeBatchLogonRight: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($SeceditDir -and (Test-Path -LiteralPath $SeceditDir)) { Remove-Item -LiteralPath $SeceditDir -Recurse -Force -ErrorAction SilentlyContinue }
}
