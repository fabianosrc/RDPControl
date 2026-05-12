<#
.SYNOPSIS
Removes a snapshot record from the store.

.DESCRIPTION
Core Store contract for snapshot removal. Enforces domain rules
and delegates persistence to the active provider implementation.

.PARAMETER Id
ID of the snapshot to remove.

.PARAMETER Force
Bypasses confirmation prompt.

.EXAMPLE
Remove-StoreSnapshot -Id 3

.OUTPUTS
None
#>
function Remove-StoreSnapshot {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [parameter()]
        [switch]$Force
    )

    begin {
        Assert-RdpEnvironment
    }

    process {

        # Delegate existence check to provider abstraction (NOT SQLite)
        $snapshot = Get-StoreSnapshot -Id $Id

        if (-not $snapshot) {
            Write-Warning "Snapshot [$Id] not found."
            return
        }

        # Domain rule stays in Core, but uses abstract store API
        $allSnapshots = Get-StoreSnapshot
        $enforced     = Get-StoreSnapshot -Enforced

        if ($allSnapshots.Count -eq 1 -and $enforced.Count -gt 0) {
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    'Cannot remove the last snapshot while enforcement is active. Disable enforcement first.'
                ),
                'LastSnapshotProtected',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $Id
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }

        if (-not ($Force -or $PSCmdlet.ShouldProcess("Snapshot [$Id]", "Remove"))) {
            return
        }

        # Core → Provider (no SQLite awareness)
        Remove-StoreSnapshotInternal -Id $Id

        Write-Verbose "Snapshot [$Id] removed."
    }
}
