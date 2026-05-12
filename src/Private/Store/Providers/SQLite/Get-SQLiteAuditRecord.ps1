<#
.SYNOPSIS
Queries audit log records from the SQLite database.

.DESCRIPTION
Retrieves audit records from the SQLite provider using optional filters.

.PARAMETER Id
Returns the audit record with the specified identifier.

.PARAMETER Operation
Filters records by operation name.

.PARAMETER Latest
Returns only the most recent audit record.

.PARAMETER Top
Limits the number of returned records.

.OUTPUTS
PSCustomObject[]
#>
function Get-SQLiteAuditRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Operation,

        [Parameter()]
        [switch]$Latest,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$Top,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
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

            # Base query
            $select = @"
                SELECT
                    id,
                    operation,
                    details,
                    performed_at,
                    performed_by
                FROM audit_log
"@

            # WHERE builder (clean + extensible)
            $where = [System.Collections.Generic.List[string]]::new()

            if ($PSBoundParameters.ContainsKey('Id')) {
                $where.Add('id = @id')
                $null = $command.Parameters.AddWithValue('@id', $Id)
            }

            if ($PSBoundParameters.ContainsKey('Operation')) {
                $where.Add('operation = @operation')
                $null = $command.Parameters.AddWithValue('@operation', $Operation)
            }

            if ($where.Count -gt 0) {
                $select += " WHERE " + ($where -join " AND ")
            }

            # Order strategy (enterprise-safe default)
            $select += " ORDER BY performed_at DESC"

            # LIMIT logic (avoid SQLite parameter issue)
            if ($Latest) {
                $select += " LIMIT 1"
            }
            elseif ($PSBoundParameters.ContainsKey('Top')) {
                $select += " LIMIT $Top"
            }

            $command.CommandText = $select

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
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'SQLiteAuditQueryFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                'audit_log'
            )

            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        finally {
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
