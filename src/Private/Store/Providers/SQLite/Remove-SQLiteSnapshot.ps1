<#
.SYNOPSIS
Removes a snapshot record from the SQLite store.

.DESCRIPTION
Deletes a snapshot record from the SQLite provider database.

.PARAMETER Id
Identifier of the snapshot record to remove.

.OUTPUTS
None
#>
function Remove-SQLiteSnapshot {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Confirmation and ShouldProcess semantics are enforced by the public cmdlet boundary.'
    )]
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [Parameter()]
        [string]$ConnectionString = (Get-StoreConnectionString)
    )

    process {
        $connection = $null
        $command    = $null

        try {
            $connection = [System.Data.SQLite.SQLiteConnection]::new($ConnectionString)
            $connection.Open()

            $command = $connection.CreateCommand()
            $command.CommandTimeout = 30

            $command.CommandText = @"
                DELETE FROM snapshots
                WHERE id = @id;
"@

            $null = $command.Parameters.Add('@id', [System.Data.DbType]::Int32).Value = $Id

            $affected = $command.ExecuteNonQuery()

            if ($affected -eq 0) {
                Write-Verbose -Message "No snapshot found with ID [$Id]."
            } else {
                Write-Verbose -Message "Snapshot [$Id] deleted successfully."
            }
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'SQLiteSnapshotRemoveFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $Id
            )

            $PSCmdlet.ThrowTerminatingError($err)
        } finally {
            if ($command) {
                $command.Dispose()
            }

            if ($connection) {
                if ($connection.State -eq 'Open') {
                    $connection.Close()
                }

                $connection.Dispose()
            }
        }
    }
}
