<#
.SYNOPSIS
Restores the target binary from a stored snapshot.

.DESCRIPTION
Retrieves a snapshot from the store and restores the original binary.
Supports restore by ID or from the latest available snapshot.

When restoring, the command:
    1. Locates the requested snapshot in the store
    2. Stops TermService if running
    3. Grants temporary write access to the binary
    4. Restores the original binary from the snapshot blob
    5. Validates the restored binary via SHA256 hash comparison
    6. Restores original ACL and service state
    7. Records the operation in the audit store

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
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Latest'
    )]
    [OutputType([pscustomobject])]
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

        $snapshotQuery = if ($PSCmdlet.ParameterSetName -eq 'ById') {
            @{ Id = $Id }
        } elseif ($Latest) {
            @{ Latest = $true }
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
                        "$targetDescription was not found."
                    ),
                    'SnapshotNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Id
                )
            )
        }

        Write-Verbose -Message "Restoring snapshot ID $($snapshotRecord.id)."

        $result = Undo-Enforcement -SnapshotId $snapshotRecord.id

        [PSCustomObject]@{
            SnapshotId = $snapshotRecord.id
            Hash       = $result.Hash
            RestoredAt = $result.RestoredAt
        }
    }
}
