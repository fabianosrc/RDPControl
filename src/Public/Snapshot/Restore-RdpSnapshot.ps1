<#
.SYNOPSIS
Restores the target binary from a stored snapshot.

.DESCRIPTION
Retrieves a snapshot from the store and restores the original binary.
Supports restore by ID or from the latest available snapshot.

.PARAMETER Id
ID of the snapshot to restore.

.PARAMETER Latest
Restores from the most recent snapshot.

.PARAMETER Force
Bypasses the confirmation prompt.

.EXAMPLE
PS C:\> Restore-RdpSnapshot -Id 3

.EXAMPLE
PS C:\> Restore-RdpSnapshot -Latest -Force

.INPUTS
None

.OUTPUTS
PSCustomObject with properties:
    SnapshotId [long]   - ID of the restored snapshot
    Hash       [string] - SHA256 of the restored binary
    RestoredAt [string] - ISO 8601 UTC timestamp
#>
function Restore-RdpSnapshot {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Latest')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new(
                        'Restore-RdpSnapshot requires elevated privileges. ' +
                        'Run PowerShell as Administrator.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }
    }

    process {
        if (-not ($Force -or $PSCmdlet.ShouldProcess('Target binary', 'Restore from snapshot'))) {
            return
        }

        $snapshot = if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $records = Get-StoreSnapshot -Id $Id

            if ($null -eq $records -or $records.Count -eq 0) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new("Snapshot [$Id] was not found."),
                        'SnapshotNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $Id
                    )
                )
            }

            $records[0]
        } else {
            $records = Get-StoreSnapshot -Latest

            if ($null -eq $records -or $records.Count -eq 0) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new('No snapshots found in the store.'),
                        'SnapshotNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $null
                    )
                )
            }

            $records[0]
        }

        $result = Undo-Enforcement

        [PSCustomObject]@{
            SnapshotId = $snapshot.id
            Hash       = $result.Hash
            RestoredAt = $result.RestoredAt
        }
    }
}
