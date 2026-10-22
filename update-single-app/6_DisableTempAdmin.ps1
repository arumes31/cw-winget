# 6_DisableTempAdmin.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Password|Result
# Disables, then deletes the temporary admin, revokes its SeBatchLogonRight and removes its profile.

$State = @'
@state@
'@.Trim()

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

# Removes the account from the SeBatchLogonRight assignment (by name or by *SID as secedit exports it)
function Revoke-BatchLogonRight {
    param([string]$Name, [string]$Sid)
    $SeceditDir = New-ProtectedWorkDir
    try {
        $TmpFile = Join-Path $SeceditDir "secedit_export.inf"
        $CfgFile = Join-Path $SeceditDir "secedit_import.inf"
        secedit /export /cfg $TmpFile /areas USER_RIGHTS | Out-Null
        $Content = Get-Content $TmpFile -Encoding Unicode
        $Changed = $false
        $Content = foreach ($line in $Content) {
            if ($line -match '^\s*SeBatchLogonRight\s*=\s*(.*)$') {
                $Entries = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $Kept = @($Entries | Where-Object { $_ -ne $Name -and $_ -ne "$env:COMPUTERNAME\$Name" -and (-not $Sid -or $_ -ne "*$Sid") })
                if ($Kept.Count -ne $Entries.Count) { $Changed = $true }
                "SeBatchLogonRight = " + ($Kept -join ",")
            }
            else { $line }
        }
        if ($Changed) {
            $Content | Set-Content $CfgFile -Encoding Unicode
            secedit /configure /db $env:windir\security\local.sdb /cfg $CfgFile /areas USER_RIGHTS | Out-Null
        }
    }
    finally {
        Remove-Item -LiteralPath $SeceditDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-UserExists {
    param([string]$Name)
    net user $Name > $null 2>&1
    return ($LASTEXITCODE -eq 0)
}

if (-not (Test-UserExists $Username)) {
    Write-Output "6|${Username}|${Password}|UserNotFound"
    exit 0
}

# Resolve the SID before deletion so the batch logon right and the profile can be cleaned up afterwards
$UserSid = $null
try {
    $UserSid = (New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, $Username)).Translate([System.Security.Principal.SecurityIdentifier]).Value
} catch {}

try {
    # Disable first so the account is locked even if deletion fails below
    try { Disable-LocalUser -Name $Username -ErrorAction Stop }
    catch {
        Start-Process net.exe -ArgumentList "user `"$Username`" /active:no" -NoNewWindow -Wait
    }

    try { Revoke-BatchLogonRight -Name $Username -Sid $UserSid }
    catch { Write-Warning "Failed to revoke SeBatchLogonRight for ${Username}: $($_.Exception.Message)" }

    # Tier 1: Modern PowerShell cmdlets
    try {
        Remove-LocalUser -Name $Username -ErrorAction Stop
    }
    catch {
        # Tier 2: ADSI WinNT provider fallback
        try {
            $Computer = [ADSI]"WinNT://$env:COMPUTERNAME"
            $Computer.Delete("user", $Username)
        }
        catch {
            # Tier 3: Legacy net user fallback
            $Proc = Start-Process net.exe -ArgumentList "user `"$Username`" /delete" -NoNewWindow -PassThru -Wait
            if ($Proc.ExitCode -ne 0) { throw "Failed to delete account ${Username} via local accounts, ADSI, or net user" }
        }
    }

    # Remove the temporary profile (C:\Users\<name> and its ProfileList entry)
    if ($UserSid) {
        try {
            Get-CimInstance Win32_UserProfile -Filter "SID = '$UserSid'" -ErrorAction Stop | Remove-CimInstance -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to remove profile for ${Username}: $($_.Exception.Message)"
        }
    }

    Write-Output "6|${Username}|${Password}|UserRemoved"
}
catch {
    if (-not (Test-UserExists $Username)) {
        Write-Output "6|${Username}|${Password}|UserRemoved"
    } else {
        Write-Error "Failed to remove user ${Username}: $($_.Exception.Message)"
        exit 1
    }
}
