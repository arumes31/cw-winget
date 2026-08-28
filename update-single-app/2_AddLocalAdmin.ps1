# 2_AddLocalAdmin.ps1 - ConnectWise Automate compatible
# Input/Output: Step|Username|Result

$State = '@state@'

$Parts = $State.Split('|')
if ($Parts.Count -lt 3) {
    Write-Error "Invalid state string. Expected Step|Username|Result"
    exit 1
}
$Username = $Parts[1].Trim()

try {
    # Robust localized Administrators group lookup
    $AdminGroup = (Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction SilentlyContinue).Name
    if (-not $AdminGroup) {
        # Fallback to SID translation and prefix stripping
        $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $Translated = $AdminSid.Translate([System.Security.Principal.NTAccount]).Value
        $AdminGroup = $Translated.Split('\')[-1]
    }
    
    # Tier 1: Modern PowerShell local user/group cmdlets
    try {
        $currentMembers = Get-LocalGroupMember -Group $AdminGroup -ErrorAction Stop
        $alreadyAdmin = $false
        if ($currentMembers) {
            foreach ($member in $currentMembers) {
                $mName = $member.Name
                if ($mName -eq $Username -or (($mName -like "*\*") -and ($mName.Split('\')[-1] -eq $Username))) {
                    $alreadyAdmin = $true
                    break
                }
            }
        }
        
        if ($alreadyAdmin) {
            Write-Output "2|${Username}|AlreadyAdmin"
            return
        }
        
        Add-LocalGroupMember -Group $AdminGroup -Member $Username -ErrorAction Stop
        Write-Output "2|${Username}|AddedToAdmin"
    }
    catch {
        # Tier 2: ADSI WinNT provider fallback
        try {
            $Group = [ADSI]"WinNT://$env:COMPUTERNAME/$AdminGroup,group"
            if ($Group.Name -eq $null) { throw "Group not found" }
            
            $isMember = $false
            # Check membership via ADSI Members collection
            try {
                $Members = $Group.Invoke("Members")
                foreach ($member in $Members) {
                    $mPath = $member.GetType().InvokeMember("ADsPath", "GetProperty", $null, $member, $null)
                    $mName = $mPath.Split('/')[-1]
                    if ($mName -eq $Username) {
                        $isMember = $true
                        break
                    }
                }
            } catch {
                # Fallback to simple membership check by attempting to add or catch error
                $isMember = $false
            }
            
            if ($isMember) {
                Write-Output "2|${Username}|AlreadyAdmin"
                return
            }
            
            # Add to group using ADSI
            $Group.Add("WinNT://$env:COMPUTERNAME/$Username")
            Write-Output "2|${Username}|AddedToAdmin"
        }
        catch {
            # Tier 3: Legacy net localgroup fallback
            try {
                # Check membership using net localgroup output
                $GroupInfo = net localgroup "$AdminGroup" 2>&1
                $MemberLine = $null
                if ($LASTEXITCODE -eq 0) {
                    $MemberLine = $GroupInfo | Where-Object { $_ -match "(^|[\s\\])$Username(\s|$)" }
                }
                
                if ($MemberLine) {
                    Write-Output "2|${Username}|AlreadyAdmin"
                    return
                }
                
                $Proc = Start-Process net.exe -ArgumentList "localgroup `"$AdminGroup`" `"$Username`" /add" -NoNewWindow -PassThru -Wait
                if ($Proc.ExitCode -ne 0) { throw "net localgroup add failed with code $($Proc.ExitCode)" }
                Write-Output "2|${Username}|AddedToAdmin"
            }
            catch {
                throw "Failed to add user ${Username} to ${AdminGroup} via local accounts, ADSI, or net localgroup: $($_.Exception.Message)"
            }
        }
    }
}
catch {
    # If the user is somehow already in the group (e.g. error thrown but user was added), we want to be safe.
    # Let's check membership one last time using the safest fallback net.exe
    try {
        $GroupInfo = net localgroup "$AdminGroup" 2>&1
        $MemberLine = $GroupInfo | Where-Object { $_ -match "(^|[\s\\])$Username(\s|$)" }
        if ($MemberLine) {
            Write-Output "2|${Username}|AlreadyAdmin"
            return
        }
    } catch {}
    
    Write-Error "Failed to add ${Username} to ${AdminGroup}: $($_.Exception.Message)"
    exit 1
}

