<#
.SYNOPSIS
Lists members of the Remote Desktop Users local group.

.DESCRIPTION
Returns all members of the 'Remote Desktop Users' local group,
including local and domain accounts.

Uses Get-LocalGroupMember for fast, modern enumeration without
legacy COM/ADSI overhead.

.EXAMPLE
PS C:\> Get-RdpUser

.INPUTS
None

.OUTPUTS
PSCustomObject[]
Contains:
- Name        [string] - account name without domain prefix
- Domain      [string] - account domain or local computer name
- ObjectClass [string] - 'User' or 'Group'
- SID         [string] - security identifier value
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
            $members = Get-LocalGroupMember -Group 'Remote Desktop Users' -ErrorAction Stop

            foreach ($member in $members) {
                # Split 'DOMAIN\Name' into parts - limit to 2 to handle edge cases
                $nameParts = $member.Name -split '\\', 2

                # If domain prefix exists use it, otherwise fall back to local computer name
                $domain = if ($nameParts.Count -eq 2) {
                    $nameParts[0]
                } else {
                    $env:COMPUTERNAME
                }

                # Return name without domain prefix for cleaner display
                $name = if ($nameParts.Count -eq 2) {
                    $nameParts[1]
                } else {
                    $member.Name
                }

                [PSCustomObject]@{
                    Name        = $name
                    Domain      = $domain
                    ObjectClass = $member.ObjectClass.ToString()
                    SID         = $member.SID.Value
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
