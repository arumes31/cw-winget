# 6_DisableTempAdmin.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Result

$State = @'
@state@
'@.Trim()

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string. Expected Step|Username|Result"
    exit 1
}
$Username = $Parts[1].Trim()

try {
    # Tier 1: Modern PowerShell cmdlets
    try {
        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        if (-not $User.Enabled) {
            Write-Output "6|${Username}|AlreadyDisabled"
            return
        }
        Disable-LocalUser -Name $Username -ErrorAction Stop
        Write-Output "6|${Username}|UserDisabled"
    }
    catch {
        # Tier 2: ADSI WinNT provider fallback
        try {
            $User = [ADSI]"WinNT://$env:COMPUTERNAME/$Username,user"
            if ($User.Name -eq $null) {
                Write-Output "6|${Username}|UserNotFound"
                return
            }
            
            $UserFlags = $User.Value("UserFlags")
            $IsDisabled = (($UserFlags -band 2) -eq 2)
            
            if ($IsDisabled) {
                Write-Output "6|${Username}|AlreadyDisabled"
                return
            }
            
            # Disable the account by setting the account disable bit (2)
            $User.Put("UserFlags", ($UserFlags -bor 2))
            $User.SetInfo()
            Write-Output "6|${Username}|UserDisabled"
        }
        catch {
            # Tier 3: Legacy net user fallback
            try {
                net user $Username > $null 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Output "6|${Username}|UserNotFound"
                    return
                }
                
                # Check status via net user output
                $UserInfo = net user $Username
                $AccountActiveLine = $UserInfo | Where-Object { $_ -match "Account active|Konto aktiv" }
                
                if ($AccountActiveLine -match "No|Nein") {
                    Write-Output "6|${Username}|AlreadyDisabled"
                    return
                }
                
                $Proc = Start-Process net.exe -ArgumentList "user `"$Username`" /active:no" -NoNewWindow -PassThru -Wait
                if ($Proc.ExitCode -ne 0) { throw "net user /active:no failed" }
                Write-Output "6|${Username}|UserDisabled"
            }
            catch {
                throw "Failed to disable account ${Username} via local accounts, ADSI, or net user: $($_.Exception.Message)"
            }
        }
    }
}
catch {
    # If the user definitely doesn't exist, we should output UserNotFound instead of failing the script.
    # We check if the exception indicates user not found.
    if ($_.Exception.Message -match "The user was not found|PrincipalNotFoundException|UserNotFound") {
        Write-Output "6|${Username}|UserNotFound"
    } else {
        Write-Error "Failed to disable user ${Username}: $($_.Exception.Message)"
        exit 1
    }
}

