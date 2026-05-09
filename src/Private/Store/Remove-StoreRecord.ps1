<#
.SYNOPSIS
Removes a snapshot record from the RDPControl SQLite store.

.DESCRIPTION
Deletes a snapshot record by ID. Blocks removal of the last snapshot when
enforcement is active - this protection is non-negotiable and cannot be
bypassed with -Force.

Audit log records are never deleted.

.PARAMETER Id
ID of the snapshot record to remove.

.PARAMETER Force
Bypasses the confirmation prompt.

.EXAMPLE
PS C:\> Remove-StoreRecord -Id 3

.EXAMPLE
PS C:\> Remove-StoreRecord -Id 3 -Force

.OUTPUTS
None
#>
function Remove-StoreRecord {
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

        $dbPath = Join-Path -Path (Get-RdpEnvironment).DatabasePath -ChildPath 'rdpcontrol.db'
    }

    process {
        $connection = $null

        try {
            $connection = [System.Data.SQLite.SQLiteConnection]::new(
                "Data Source=$dbPath;Version=3;"
            )

            $connection.Open()

            # Verify record exists
            $checkCmd = $connection.CreateCommand()
            $checkCmd.CommandText = 'SELECT COUNT(*) FROM snapshots WHERE id = @id'
            $checkCmd.Parameters.AddWithValue('@id', $Id) | Out-Null
            [long]$count = $checkCmd.ExecuteScalar()

            if ($count -eq 0) {
                Write-Warning -Message "Snapshot record [$Id] not found."
                return
            }

            # Count total snapshots
            $countCmd = $connection.CreateCommand()
            $countCmd.CommandText = 'SELECT COUNT(*) FROM snapshots'
            [long]$totalSnapshots = $countCmd.ExecuteScalar()

            # Check if enforcement is active
            $enforcedCmd = $connection.CreateCommand()
            $enforcedCmd.CommandText = 'SELECT COUNT(*) FROM snapshots WHERE enforced = 1'
            [long]$enforcedCount = $enforcedCmd.ExecuteScalar()

            # Block removal of last snapshot when enforcement is active
            # Non-negotiable - cannot be bypassed with -Force
            if ($totalSnapshots -eq 1 -and $enforcedCount -gt 0) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'Cannot remove the last snapshot while enforcement is active. ' +
                        'Disable enforcement first.'
                    ),
                    'LastSnapshotProtected',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $Id
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            if (-not ($Force -or $PSCmdlet.ShouldProcess("Snapshot [$Id]", 'Remove'))) {
                return
            }

            $deleteCmd = $connection.CreateCommand()
            $deleteCmd.CommandText = 'DELETE FROM snapshots WHERE id = @id'
            $deleteCmd.Parameters.AddWithValue('@id', $Id) | Out-Null
            $deleteCmd.ExecuteNonQuery() | Out-Null

            Write-Verbose -Message "Snapshot record [$Id] removed."
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'StoreRemoveFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $Id
            )

            $PSCmdlet.ThrowTerminatingError($err)
        } finally {
            if ($null -ne $connection) {
                $connection.Close()
                $connection.Dispose()
            }
        }
    }
}
