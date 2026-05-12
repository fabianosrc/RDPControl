<#
.SYNOPSIS
Queries snapshot records from the SQLite store.

.DESCRIPTION
Retrieves snapshot records from the SQLite provider database using
optional filtering criteria.

.PARAMETER Id
Returns the snapshot with the specified ID.

.PARAMETER Sha256
Returns the snapshot matching the specified SHA256 hash.

.PARAMETER Enforced
Filters snapshots by enforcement state.

.PARAMETER Latest
Returns only the most recent snapshot.

.PARAMETER Top
Limits the number of returned records.

.OUTPUTS
PSCustomObject
#>
function Get-SQLiteSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Sha256,

        [Parameter()]
        [nullable[bool]]$Enforced,

        [Parameter()]
        [switch]$Latest,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$Top,

        [Parameter()]
        [string]$ConnectionString = (Get-StoreConnectionString)
    )

    begin {
        $connection = $null
        $command    = $null
        $reader     = $null
    }

    process {
        try {
            $connection = [System.Data.SQLite.SQLiteConnection]::new($ConnectionString)
            $connection.Open()

            $command = $connection.CreateCommand()
            $command.CommandTimeout = 30

            $sql = @"
                SELECT
                    id,
                    binary_path,
                    binary_version,
                    os_build,
                    sha256,
                    enforced,
                    created_at
                FROM snapshots
"@

            $where = [System.Collections.Generic.List[string]]::new()

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
                $null = $command.Parameters.AddWithValue('@enforced', [int]$Enforced)
            }

            if ($where.Count -gt 0) {
                $sql += " WHERE " + ($where -join " AND ")
            }

            $sql += " ORDER BY created_at DESC"

            if ($Latest) {
                $sql += " LIMIT 1"
            } elseif ($PSBoundParameters.ContainsKey('Top')) {
                $sql += " LIMIT $Top"
            }

            $command.CommandText = $sql

            $reader = $command.ExecuteReader()

            while ($reader.Read()) {
                $obj = [ordered]@{}

                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    $obj[$reader.GetName($i)] = if ($reader.IsDBNull($i)) {
                        $null
                    } else {
                        $reader.GetValue($i)
                    }
                }

                [pscustomobject]$obj
            }
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'SQLiteSnapshotQueryFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                'snapshots'
            )

            $PSCmdlet.ThrowTerminatingError($err)
        } finally {
            if ($reader) {
                $reader.Dispose()
            }

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
