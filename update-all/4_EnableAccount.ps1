# 4_EnableAccount.ps1 - ConnectWise Automate compatible
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
    # Tier 1: Modern PowerShell cmdlets
    try {
        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        if ($User.Enabled) {
            Write-Output "4|${Username}|${Password}|AlreadyEnabled"
            return
        }
        Enable-LocalUser -Name $Username -ErrorAction Stop
        Write-Output "4|${Username}|${Password}|AccountEnabled"
    }
    catch {
        # Tier 2: ADSI WinNT provider fallback
        try {
            $User = [ADSI]"WinNT://$env:COMPUTERNAME/$Username,user"
            if ($User.Name -eq $null) { throw "User not found" }
            
            # Check UserFlags to see if account is disabled (ADS_UF_ACCOUNTDISABLE is 2)
            $UserFlags = $User.Value("UserFlags")
            $IsDisabled = (($UserFlags -band 2) -eq 2)
            
            if (-not $IsDisabled) {
                Write-Output "4|${Username}|${Password}|AlreadyEnabled"
                return
            }
            
            # Enable the account by clearing the account disable bit (2)
            $User.Put("UserFlags", ($UserFlags -bxor 2))
            $User.SetInfo()
            Write-Output "4|${Username}|${Password}|AccountEnabled"
        }
        catch {
            # Tier 3: Legacy net user fallback
            try {
                net user $Username > $null 2>&1
                if ($LASTEXITCODE -ne 0) { throw "User not found" }
                
                # Check status via net user output
                $UserInfo = net user $Username
                $AccountActiveLine = $UserInfo | Where-Object { $_ -match "Account active|Konto aktiv" }
                
                if ($AccountActiveLine -match "Yes|Ja") {
                    Write-Output "4|${Username}|${Password}|AlreadyEnabled"
                    return
                }
                
                $Proc = Start-Process net.exe -ArgumentList "user `"$Username`" /active:yes" -NoNewWindow -PassThru -Wait
                if ($Proc.ExitCode -ne 0) { throw "net user /active:yes failed" }
                Write-Output "4|${Username}|${Password}|AccountEnabled"
            }
            catch {
                throw "Failed to enable account ${Username} via local accounts, ADSI, or net user: $($_.Exception.Message)"
            }
        }
    }
}
catch {
    Write-Error "Failed to enable account ${Username}: $($_.Exception.Message)"
    exit 1
}
