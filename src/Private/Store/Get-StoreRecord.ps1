<#
.SYNOPSIS
Queries records from the RDPControl SQLite store.

.DESCRIPTION
Retrieves snapshot or audit log records from the database. Supports filtering
by ID, SHA256, enforced state, and result limiting.

.PARAMETER Snapshot
Queries the snapshots table.

.PARAMETER Audit
Queries the audit_log table.

.PARAMETER Id
Returns the record with the specified ID.

.PARAMETER Sha256
Returns the snapshot matching the specified SHA256 hash.

.PARAMETER Enforced
Filters snapshots by enforced state.

.PARAMETER Latest
Returns only the most recent record.

.PARAMETER Top
Returns the specified number of most recent records.

.EXAMPLE
PS C:\> Get-StoreRecord -Snapshot -Latest

.EXAMPLE
PS C:\> Get-StoreRecord -Audit -Top 10

.OUTPUTS
PSCustomObject[]
#>
function Get-StoreRecord {
    [CmdletBinding(DefaultParameterSetName = 'Snapshot')]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Snapshot')]
        [Parameter(Mandatory, ParameterSetName = 'SnapshotById')]
        [Parameter(Mandatory, ParameterSetName = 'SnapshotByHash')]
        [Parameter(Mandatory, ParameterSetName = 'SnapshotLatest')]
        [switch]$Snapshot,

        [Parameter(Mandatory, ParameterSetName = 'Audit')]
        [Parameter(Mandatory, ParameterSetName = 'AuditLatest')]
        [switch]$Audit,

        [Parameter(Mandatory, ParameterSetName = 'SnapshotById')]
        [Parameter(Mandatory, ParameterSetName = 'AuditById')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [Parameter(Mandatory, ParameterSetName = 'SnapshotByHash')]
        [ValidateNotNullOrEmpty()]
        [string]$Sha256,

        [Parameter(ParameterSetName = 'Snapshot')]
        [bool]$Enforced,

        [Parameter(Mandatory, ParameterSetName = 'SnapshotLatest')]
        [Parameter(Mandatory, ParameterSetName = 'AuditLatest')]
        [switch]$Latest,

        [Parameter(ParameterSetName = 'Snapshot')]
        [Parameter(ParameterSetName = 'Audit')]
        [ValidateRange(1, 1000)]
        [int]$Top
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
            $command = $connection.CreateCommand()

            $limit = if ($PSBoundParameters.ContainsKey('Top')) {
                [int]$Top
            } else {
                $null
            }

            if ($Snapshot) {
                $command.CommandText =
                    'SELECT id, dll_path, dll_version, os_build, sha256, enforced, created_at FROM snapshots'

                $conditions = [System.Collections.Generic.List[string]]::new()

                if ($PSBoundParameters.ContainsKey('Id')) {
                    $conditions.Add('id = @id')
                    $command.Parameters.AddWithValue('@id', $Id) | Out-Null
                }

                if ($PSBoundParameters.ContainsKey('Sha256')) {
                    $conditions.Add('sha256 = @sha256')
                    $command.Parameters.AddWithValue('@sha256', $Sha256) | Out-Null
                }

                if ($PSBoundParameters.ContainsKey('Enforced')) {
                    $conditions.Add('enforced = @enforced')
                    $command.Parameters.AddWithValue('@enforced', [int]([bool]$Enforced)) | Out-Null
                }

                if ($conditions.Count -gt 0) {
                    $command.CommandText += ' WHERE ' + ($conditions -join ' AND ')
                }
            } elseif ($Audit) {
                $command.CommandText =
                    'SELECT id, operation, details, performed_at, performed_by FROM audit_log'

                if ($PSBoundParameters.ContainsKey('Id')) {
                    $command.CommandText += ' WHERE id = @id'
                    $command.Parameters.AddWithValue('@id', $Id) | Out-Null
                }
            }

            $command.CommandText += ' ORDER BY id DESC'

            if ($Latest) {
                $command.CommandText += ' LIMIT 1'
            } elseif ($null -ne $limit) {
                $command.CommandText += " LIMIT $limit"
            }

            Write-Verbose -Message "Query: $($command.CommandText)"

            $reader  = $command.ExecuteReader()
            $results = [System.Collections.Generic.List[object]]::new()

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

                    $results.Add([PSCustomObject]$record)
                }
            } finally {
                $reader.Dispose()
            }

            Write-Verbose -Message "Retrieved $($results.Count) record(s)."

            return $results.ToArray()
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'StoreQueryFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $dbPath
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
