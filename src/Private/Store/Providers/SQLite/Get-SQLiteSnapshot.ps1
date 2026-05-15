<#
.SYNOPSIS
Queries snapshot records from the SQLite database.

.DESCRIPTION
SQLite provider implementation for snapshot queries.
Use -IncludeBlob only when the binary content is needed (e.g. restore).
Omitting -IncludeBlob avoids reading large binary data unnecessarily.

.PARAMETER Id
Returns the snapshot with the specified ID.

.PARAMETER Sha256
Returns the snapshot matching the specified SHA256 hash.

.PARAMETER Enforced
Filters by enforced state.

.PARAMETER Latest
Returns only the most recent snapshot.

.PARAMETER Top
Returns the specified number of most recent snapshots.

.PARAMETER IncludeBlob
Includes the binary_blob column in the result.
Use only when binary content is required (e.g. restore operations).

.OUTPUTS
PSCustomObject[]
#>
function Get-SQLiteSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter()]
        [int]$Id,

        [Parameter()]
        [string]$Sha256,

        [Parameter()]
        [bool]$Enforced,

        [Parameter()]
        [switch]$Latest,

        [Parameter()]
        [int]$Top,

        [Parameter()]
        [switch]$IncludeBlob
    )

    process {
        $connection = $null

        try {
            $connection = [System.Data.SQLite.SQLiteConnection]::new((Get-StoreConnectionString))
            $connection.Open()

            $command    = $connection.CreateCommand()
            $where = [System.Collections.Generic.List[string]]::new()

            $columns = 'id, binary_path, binary_version, os_build, sha256, enforced, created_at'

            if ($IncludeBlob) {
                $columns += ', binary_blob'
            }

            $sql = "SELECT $columns FROM snapshots"

            if ($PSBoundParameters.ContainsKey('Id')) {
                $where.Add('id = @id')
                $command.Parameters.AddWithValue('@id', $Id) | Out-Null
            }

            if ($PSBoundParameters.ContainsKey('Sha256')) {
                $where.Add('sha256 = @sha256')
                $command.Parameters.AddWithValue('@sha256', $Sha256) | Out-Null
            }

            if ($PSBoundParameters.ContainsKey('Enforced')) {
                $where.Add('enforced = @enforced')
                $command.Parameters.AddWithValue('@enforced', [int]([bool]$Enforced)) | Out-Null
            }

            if ($where.Count -gt 0) {
                $sql += ' WHERE ' + ($where -join ' AND ')
            }

            $sql += ' ORDER BY id DESC'

            if ($Latest) {
                $sql += ' LIMIT 1'
            } elseif ($PSBoundParameters.ContainsKey('Top')) {
                $sql += ' LIMIT @top'
                $command.Parameters.AddWithValue('@top', $Top) | Out-Null
            }

            $command.CommandText = $sql
            $reader              = $command.ExecuteReader()
            $results             = [System.Collections.Generic.List[object]]::new()

            try {
                while ($reader.Read()) {
                    $record = [ordered]@{}
                    for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                        $record[$reader.GetName($i)] = if ($reader.IsDBNull($i)) {
                            $null
                        } else {
                            $reader.GetValue($i)
                        }
                    }

                    $results.Add([pscustomobject]$record)
                }
            } finally {
                $reader.Dispose()
            }

            $results.ToArray()
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'SQLiteSnapshotQueryFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    'snapshots'
                )
            )
        } finally {
            if ($null -ne $connection) {
                $connection.Close()
                $connection.Dispose()
            }
        }
    }
}
