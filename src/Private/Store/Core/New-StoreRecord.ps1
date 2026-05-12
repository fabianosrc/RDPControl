<#
.SYNOPSIS
Inserts a record into the RDPControl SQLite store.

.DESCRIPTION
Inserts either a snapshot record (binary blob with metadata) or an audit log
entry into the database. Uses parameterized queries to prevent SQL injection.

The database path is resolved from the initialized environment on each call.
Timestamp is computed once in the begin block for consistency across records.

.PARAMETER Snapshot
Inserts a snapshot record.

.PARAMETER Audit
Inserts an audit log entry.

.PARAMETER DllPath
Full path to the target binary file. Required for snapshot records.

.PARAMETER DllVersion
File version of the binary. Required for snapshot records.

.PARAMETER OsBuild
Windows OS version string. Required for snapshot records.

.PARAMETER Sha256
SHA256 hash of the binary blob. Required for snapshot records.

.PARAMETER Blob
Raw bytes of the binary. Required for snapshot records.

.PARAMETER Enforced
Whether the snapshot represents an enforced state. Defaults to $false.

.PARAMETER Operation
Operation name for audit log entries. Required for audit records.

.PARAMETER Details
Optional details string for audit log entries.

.EXAMPLE
PS C:\> New-StoreRecord -Snapshot -DllPath $path -DllVersion $ver -OsBuild $os -Sha256 $hash -Blob $bytes

.EXAMPLE
PS C:\> New-StoreRecord -Audit -Operation 'Invoke-Enforcement' -Details 'WriteOffset=0x001E815'

.INPUTS
None

.OUTPUTS
System.Int64 - the inserted record ID
#>
function New-StoreRecord {
    [CmdletBinding(DefaultParameterSetName = 'Snapshot', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([long])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Snapshot')]
        [switch]$Snapshot,

        [Parameter(Mandatory, ParameterSetName = 'Audit')]
        [switch]$Audit,

        [Parameter(Mandatory, ParameterSetName = 'Snapshot')]
        [ValidateNotNullOrEmpty()]
        [string]$DllPath,

        [Parameter(Mandatory, ParameterSetName = 'Snapshot')]
        [ValidateNotNullOrEmpty()]
        [string]$DllVersion,

        [Parameter(Mandatory, ParameterSetName = 'Snapshot')]
        [ValidateNotNullOrEmpty()]
        [string]$OsBuild,

        [Parameter(Mandatory, ParameterSetName = 'Snapshot')]
        [ValidateNotNullOrEmpty()]
        [string]$Sha256,

        [Parameter(Mandatory, ParameterSetName = 'Snapshot')]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Blob,

        [Parameter(ParameterSetName = 'Snapshot')]
        [bool]$Enforced = $false,

        [Parameter(Mandatory, ParameterSetName = 'Audit')]
        [ValidateNotNullOrEmpty()]
        [string]$Operation,

        [Parameter(ParameterSetName = 'Audit')]
        [string]$Details
    )

    begin {
        Assert-RdpEnvironment

        $dbPath = Join-Path -Path (Get-RdpEnvironment).DatabasePath -ChildPath 'rdpcontrol.db'
        $now    = (Get-Date).ToUniversalTime().ToString('o')

        Write-Verbose -Message "Target database: $dbPath"
    }

    process {
        $actionTarget = if ($Snapshot) {
            "Snapshot record for $DllPath"
        } elseif ($Audit) {
            "Audit record: $Operation"
        }

        if (-not $PSCmdlet.ShouldProcess($actionTarget, 'Insert SQLite record')) {
            return
        }

        $connection = $null

        try {
            $connection = [System.Data.SQLite.SQLiteConnection]::new(
                "Data Source=$dbPath;Version=3;"
            )

            $connection.Open()
            $command = $connection.CreateCommand()

            if ($Snapshot) {
                $command.CommandText = @"
                    INSERT INTO snapshots (dll_path, dll_version, os_build, sha256, enforced, created_at, blob)
                    VALUES (@dll_path, @dll_version, @os_build, @sha256, @enforced, @created_at, @blob);
                    SELECT last_insert_rowid();
"@
                $params = @{
                    '@dll_path'    = $DllPath
                    '@dll_version' = $DllVersion
                    '@os_build'    = $OsBuild
                    '@sha256'      = $Sha256
                    '@enforced'    = [int]$Enforced
                    '@created_at'  = $now
                    '@blob'        = $Blob
                }

                Write-Verbose -Message "Inserting snapshot: $DllPath ($Sha256)"
            } elseif ($Audit) {
                $command.CommandText = @"
                    INSERT INTO audit_log (operation, details, performed_at, performed_by)
                    VALUES (@operation, @details, @performed_at, @performed_by);
                    SELECT last_insert_rowid();
"@
                $params = @{
                    '@operation'    = $Operation
                    '@details'      = $Details
                    '@performed_at' = $now
                    '@performed_by' = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                }

                Write-Verbose -Message "Inserting audit record: $Operation"
            }

            foreach ($kv in $params.GetEnumerator()) {
                $command.Parameters.AddWithValue($kv.Key, $kv.Value) | Out-Null
            }

            [long]$command.ExecuteScalar()
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'StoreInsertFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
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
