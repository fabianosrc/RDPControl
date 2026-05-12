<#
.SYNOPSIS
Inserts a snapshot record into the SQLite store.

.DESCRIPTION
Persists a binary snapshot into the SQLite provider database and
returns the inserted record identifier.

.PARAMETER BinaryPath
Full path to the binary.

.PARAMETER BinaryVersion
Version of the binary file.

.PARAMETER OsBuild
Windows OS build string.

.PARAMETER Sha256
SHA256 hash of the binary.

.PARAMETER BinaryBlob
Raw binary bytes.

.PARAMETER Enforced
Indicates whether the snapshot represents an enforced state.

.OUTPUTS
System.Int64
#>
function New-SQLiteSnapshot {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([long])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BinaryPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BinaryVersion,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OsBuild,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Sha256,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [byte[]]$BinaryBlob,

        [Parameter(Mandatory)]
        [bool]$Enforced,

        [Parameter()]
        [string]$ConnectionString = (Get-StoreConnectionString)
    )

    process {

        if (-not $PSCmdlet.ShouldProcess($BinaryPath, "Insert snapshot record")) {
            return
        }

        $connection  = $null
        $transaction = $null
        $command     = $null

        try {
            $connection = [System.Data.SQLite.SQLiteConnection]::new($ConnectionString)
            $connection.Open()

            $transaction = $connection.BeginTransaction()

            $command = $connection.CreateCommand()
            $command.Transaction = $transaction
            $command.CommandTimeout = 30

            $createdAt = [DateTime]::UtcNow.ToString('o')

            $command.CommandText = @"
                INSERT INTO snapshots (
                    binary_path,
                    binary_version,
                    os_build,
                    sha256,
                    enforced,
                    created_at,
                    binary_blob
                ) VALUES (
                    @binary_path,
                    @binary_version,
                    @os_build,
                    @sha256,
                    @enforced,
                    @created_at,
                    @binary_blob
                );
"@

            $null = $command.Parameters.Add('@binary_path',    [System.Data.DbType]::String).Value = $BinaryPath
            $null = $command.Parameters.Add('@binary_version', [System.Data.DbType]::String).Value = $BinaryVersion
            $null = $command.Parameters.Add('@os_build',       [System.Data.DbType]::String).Value = $OsBuild
            $null = $command.Parameters.Add('@sha256',         [System.Data.DbType]::String).Value = $Sha256
            $null = $command.Parameters.Add('@enforced',       [System.Data.DbType]::Int32).Value  = [int]$Enforced
            $null = $command.Parameters.Add('@created_at',     [System.Data.DbType]::String).Value = $createdAt
            $null = $command.Parameters.Add('@binary_blob',    [System.Data.DbType]::Binary).Value = $BinaryBlob

            $null = $command.ExecuteNonQuery()

            $command.CommandText = "SELECT last_insert_rowid();"
            $id = $command.ExecuteScalar()

            $transaction.Commit()

            return [long]$id
        } catch {
            if ($transaction) {
                try {
                    $transaction.Rollback()
                } catch {
                    Write-Warning -Message "Rollback failed: $($_.Exception.Message)"
                }
            }

            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'SQLiteSnapshotInsertFailed',
                [System.Management.Automation.ErrorCategory]::WriteError, @{
                    BinaryPath = $BinaryPath
                    Sha256     = $Sha256
                }
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
