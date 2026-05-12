<#
.SYNOPSIS
Removes users or groups from the Remote Desktop Users local group.

.DESCRIPTION
Removes one or more local or domain accounts from the 'Remote Desktop Users'
local group. Skips accounts that are not members.

Accepts array input and pipeline input.

.PARAMETER Identity
One or more account names to remove. Accepts 'Username' or 'DOMAIN\Username' format.

.PARAMETER Force
Bypasses the confirmation prompt.

.EXAMPLE
PS C:\> Remove-RdpUser -Identity 'User1'

.EXAMPLE
PS C:\> Remove-RdpUser -Identity 'User1', 'DOMAIN\User2'

.EXAMPLE
PS C:\> 'User1', 'DOMAIN\User2' | Remove-RdpUser -Force

.INPUTS
System.String[]

.OUTPUTS
None
#>
function Remove-RdpUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.UnauthorizedAccessException]::new(
                    'Remove-RdpUser requires elevated privileges. ' +
                    'Run PowerShell as Administrator.'
                ),
                'ElevationRequired',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }

    process {
        foreach ($id in $Identity) {
            try {
                $existingMembers = Get-RdpUser | Select-Object -ExpandProperty Name

                if ($existingMembers -notcontains $id -and $existingMembers -notcontains ($id -split '\\')[-1]) {
                    Write-Warning -Message "[$id] is not a member of Remote Desktop Users. Skipping."
                    continue
                }

                if (-not ($Force -or $PSCmdlet.ShouldProcess($id, 'Remove from Remote Desktop Users'))) {
                    continue
                }

                Remove-LocalGroupMember -Group 'Remote Desktop Users' -Member $id -ErrorAction Stop

                New-StoreAuditRecord -Operation 'Remove-RdpUser' -Details "Identity=$id;Action=Removed" | Out-Null

                Write-Verbose -Message "[$id] removed from Remote Desktop Users."
            } catch {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'RemoveRdpUserFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $id
                )

                $PSCmdlet.WriteError($err)
            }
        }
    }
}
