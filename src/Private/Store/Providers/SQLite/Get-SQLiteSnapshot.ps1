<#
.SYNOPSIS
Queries snapshot records from the SQLite database.

.DESCRIPTION
SQLite provider implementation for snapshot queries.

Supports filtering by:
    - Snapshot ID
    - SHA256 hash
    - Enforcement state
    - Latest snapshot
    - Top N records

Binary blob retrieval is optional and disabled by default to avoid
unnecessary memory allocation and database IO overhead.

.PARAMETER Id
Returns the snapshot with the specified ID.

.PARAMETER Sha256
Returns snapshots matching the specified SHA256 hash.

.PARAMETER Enforced
Filters snapshots by enforcement state.

.PARAMETER Latest
Returns only the most recent snapshot.

.PARAMETER Top
Limits the number of returned records.

.PARAMETER IncludeBlob
Includes the binary_blob column in the result set.
Use only when binary content is required (e.g. restore operations).

.EXAMPLE
PS C:\> Get-SQLiteSnapshot -Latest

.EXAMPLE
PS C:\> Get-SQLiteSnapshot -Enforced $false

.EXAMPLE
PS C:\> Get-SQLiteSnapshot -Id 1 -IncludeBlob

.OUTPUTS
PSCustomObject[]
#>
function Get-SQLiteSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Sha256,

        [Parameter()]
        [bool]$Enforced,

        [Parameter()]
        [switch]$Latest,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Top,

        [Parameter()]
        [switch]$IncludeBlob
    )

    process {
        $connection = $null
        $command    = $null
        $reader     = $null

        try {
            $connection = [System.Data.SQLite.SQLiteConnection]::new((Get-StoreConnectionString))
            $connection.Open()

            $command = $connection.CreateCommand()
            $command.CommandTimeout = 30

            $where = [System.Collections.Generic.List[string]]::new()

            $columns = @(
                'id'
                'binary_path'
                'binary_version'
                'os_build'
                'sha256'
                'enforced'
                'created_at'
            )

            if ($IncludeBlob) {
                $columns += 'binary_blob'
            }

            $columnList = $columns -join ', '
            $sql        = "SELECT $columnList FROM snapshots"

            if ($PSBoundParameters.ContainsKey('Id')) {
                $where.Add('id = @id')
                $null = $command.Parameters.AddWithValue('@id', $Id)
            }

            if ($PSBoundParameters.ContainsKey('Sha256')) {
                $where.Add('sha256 = @sha256')
                $null = $command.Parameters.AddWithValue('@sha256', $Sha256)
            }

            if ($PSBoundParameters.ContainsKey('Enforced')) {
                $where.Add('enforced = @enforced')
                $null = $command.Parameters.AddWithValue('@enforced', [int][bool]$Enforced)
            }

            if ($where.Count -gt 0) {
                $sql += ' WHERE ' + ($where -join ' AND ')
            }

            $sql += ' ORDER BY id DESC'

            if ($Latest) {
                $sql += ' LIMIT 1'
            } elseif ($PSBoundParameters.ContainsKey('Top')) {
                $sql += ' LIMIT @top'
                $null = $command.Parameters.AddWithValue('@top', $Top)
            }

            $command.CommandText = $sql

            Write-Verbose -Message "Executing SQLite snapshot query: $($command.CommandText)"

            $reader  = $command.ExecuteReader()
            $results = [System.Collections.Generic.List[object]]::new()

            while ($reader.Read()) {
                $record = [ordered]@{
                    PSTypeName = 'RDPControl.SnapshotInfo'
                }

                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    $columnName = $reader.GetName($i)

                    $record[$columnName] = if ($reader.IsDBNull($i)) {
                        $null
                    } elseif ($columnName -eq 'enforced') {
                        [bool]$reader.GetValue($i)
                    } else {
                        $reader.GetValue($i)
                    }
                }

                $results.Add([pscustomobject]$record)
            }

            Write-Verbose -Message "SQLite snapshot query returned $($results.Count) record(s)."

            return $results.ToArray()
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
            if ($null -ne $reader) {
                try {
                    $reader.Close()
                } catch {
                    Write-Verbose -Message "Failed to close SQLite reader: $($_.Exception.Message)"
                }

                $reader.Dispose()
            }

            if ($null -ne $command) {
                $command.Dispose()
            }

            if ($null -ne $connection) {
                try {
                    if ($connection.State -eq 'Open') {
                        $connection.Close()
                    }
                } finally {
                    $connection.Dispose()
                }
            }
        }
    }
}
