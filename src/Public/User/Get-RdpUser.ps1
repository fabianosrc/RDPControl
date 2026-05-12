<#
.SYNOPSIS
Lists members of the Remote Desktop Users local group.

.DESCRIPTION
Returns all members of the 'Remote Desktop Users' local group,
including local and domain accounts.

.EXAMPLE
PS C:> Get-RdpUser

.INPUTS
None

.OUTPUTS
PSCustomObject[]
Contains:
- Name
- Domain
- ObjectClass
- SID

.NOTES
Uses WinNT ADSI provider (legacy compatibility layer).
#>

function Get-RdpUser {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param ()

    begin {
        Assert-RdpEnvironment
    }

    process {
        try {
            $group = [adsi]"WinNT://$env:COMPUTERNAME/Remote Desktop Users,group"

            foreach ($member in $group.Members()) {
                $name  = $member.Name
                $class = $member.Class
                $path  = $member.ADsPath

                # safer domain extraction (no regex hack)
                $domain = if ($path -match '^WinNT://([^/]+)/') {
                    $matches[1]
                } else {
                    $env:COMPUTERNAME
                }

                $sid = $null

                try {
                    $ntAccount = [System.Security.Principal.NTAccount]::new($domain, $name)
                    $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
                } catch {
                    # SID resolution failure is not fatal
                    $sid = $null
                }

                [PSCustomObject]@{
                    Name        = $name
                    Domain      = $domain
                    ObjectClass = $class
                    SID         = $sid
                }
            }
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'GetRdpUserFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    'Remote Desktop Users'
                )
            )
        }
    }
}
