<#
.SYNOPSIS
Restores the target binary from a stored snapshot.

.DESCRIPTION
Retrieves a pre-enforcement snapshot from the store and restores the
original binary. Only pre-enforcement snapshots are valid restore points.

When restoring, the command:
    1. Locates the requested snapshot in the store
    2. Validates the snapshot is a pre-enforcement restore point
    3. Stops TermService if running
    4. Grants temporary write access to the binary
    5. Restores the original binary from the snapshot blob
    6. Validates the restored binary via SHA256 hash comparison
    7. Restores original ACL and service state
    8. Records the operation in the audit store

.PARAMETER Id
ID of the snapshot to restore.

.PARAMETER Latest
Restores from the most recent pre-enforcement snapshot.

.PARAMETER Force
Bypasses the confirmation prompt.

.EXAMPLE
PS C:\> Restore-RdpSnapshot -Latest

.EXAMPLE
PS C:\> Restore-RdpSnapshot -Id 1 -Force

.INPUTS
None

.OUTPUTS
RDPControl.RestoreResult
#>
function Restore-RdpSnapshot {
    [CmdletBinding( SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Latest')]
    [OutputType('RDPControl.RestoreResult')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$Id,

        [Parameter(Mandatory, ParameterSetName = 'Latest')]
        [switch]$Latest,

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
        if (-not ($Force -or $PSCmdlet.ShouldProcess('termsrv.dll', 'Restore binary from snapshot'))) {
            return
        }

        # Only pre-enforcement snapshots are valid restore points
        $snapshotQuery = if ($PSCmdlet.ParameterSetName -eq 'ById') {
            @{
                Id       = $Id
                Enforced = $false
            }
        } elseif ($Latest) {
            @{
                Latest   = $true
                Enforced = $false
            }
        }

        $snapshotRecord = @(Get-StoreSnapshot @snapshotQuery) | Select-Object -First 1

        if ($null -eq $snapshotRecord) {
            $targetDescription = if ($PSCmdlet.ParameterSetName -eq 'ById') {
                "Snapshot [$Id]"
            } else {
                'Latest snapshot'
            }

            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        "$targetDescription was not found or is not a valid restore point."
                    ),
                    'SnapshotNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Id
                )
            )
        }

        Write-Verbose -Message "Restoring snapshot ID $($snapshotRecord.id)."

        $result = Undo-Enforcement -SnapshotId $snapshotRecord.id

        return [PSCustomObject]@{
            PSTypeName = 'RDPControl.RestoreResult'
            SnapshotId = $snapshotRecord.id
            Hash       = $result.Hash
            RestoredAt = $result.RestoredAt
        }
    }
}
