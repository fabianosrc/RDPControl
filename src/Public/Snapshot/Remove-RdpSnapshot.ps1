<#
.SYNOPSIS
Removes a stored snapshot.

.DESCRIPTION
Removes a snapshot record from the store by ID.

Blocks removal of the last snapshot when enforcement is active.
This protection cannot be bypassed with -Force.

.PARAMETER Id
ID of the snapshot to remove.

.PARAMETER Force
Bypasses the confirmation prompt.

.EXAMPLE
PS C:\> Remove-RdpSnapshot -Id 3

.EXAMPLE
PS C:\> Remove-RdpSnapshot -Id 3 -Force

.INPUTS
None

.OUTPUTS
None
#>
function Remove-RdpSnapshot {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Assert-RdpEnvironment
    }

    process {
        if (-not ($Force -or $PSCmdlet.ShouldProcess("Snapshot [$Id]", 'Remove'))) {
            return
        }

        Remove-StoreSnapshot -Id $Id -Force:$Force
    }
}
