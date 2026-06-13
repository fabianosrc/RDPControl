<#
.SYNOPSIS
Lists members of the Remote Desktop Users local group.

.DESCRIPTION
Returns all members of the 'Remote Desktop Users' local group,
including local and domain accounts.

Uses Get-LocalGroupMember for fast, modern enumeration without
legacy COM/ADSI overhead.

If a member's SID cannot be resolved to an account name (for example,
a domain account that was deleted, or a domain trust that is
unavailable), the orphaned SID is returned as-is in the 'Name' and
'Identity' properties with 'Domain' set to $null, and a warning is
written. This allows the caller to identify and remove orphaned entries
via Remove-RdpUser, while still enumerating all other valid members.

.EXAMPLE
PS C:\> Get-RdpUser

.EXAMPLE
PS C:\> Get-RdpUser | Remove-RdpUser

.INPUTS
None

.OUTPUTS
PSCustomObject[]
Contains:
- Identity    [string] - 'DOMAIN\Name' for domain accounts, or
                          'COMPUTERNAME\Name' for local accounts (the
                          local computer name is always included as the
                          domain segment), or the raw SID string if the
                          entry is orphaned. Suitable for use as the
                          -Identity parameter of Add-RdpUser and
                          Remove-RdpUser, including via pipeline.
- Name        [string] - account name without domain prefix, or the
                          raw SID string if the entry is orphaned
- Domain      [string] - account domain or local computer name, or
                          $null if the entry is orphaned
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
            $members = Get-LocalGroupMember -Group 'Remote Desktop Users'

            foreach ($member in $members) {
                $sidValue = $member.SID.Value

                # Detect orphaned SIDs: when the principal cannot be resolved,
                # Get-LocalGroupMember returns the SID string itself as Name.
                if ($member.Name -eq $sidValue) {
                    Write-Warning -Message (
                        "Member [$sidValue] of Remote Desktop Users could not be resolved to an account name." +
                        "The account may have been deleted or its domain is unreachable."
                    )

                    [PSCustomObject]@{
                        Identity    = $sidValue
                        Name        = $sidValue
                        Domain      = $null
                        ObjectClass = $member.ObjectClass.ToString()
                        SID         = $sidValue
                    }

                    continue
                }

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
                    Identity    = "$domain\$name"
                    Name        = $name
                    Domain      = $domain
                    ObjectClass = $member.ObjectClass.ToString()
                    SID         = $sidValue
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
