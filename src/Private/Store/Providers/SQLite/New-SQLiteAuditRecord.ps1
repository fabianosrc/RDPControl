<#
.SYNOPSIS
Writes an audit record to the SQLite store.

.DESCRIPTION
SQLite Provider implementation for audit logging.
Responsible for persistence, timestamp generation, and identity capture.

This function is NOT part of the public contract layer and must only
be called by Core Store cmdlets.

.PARAMETER Operation
Operation name to record.

.PARAMETER Details
Optional operation details.

.OUTPUTS
System.Int64 - Inserted record ID
#>
function New-SQLiteAuditRecord {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Internal provider layer controlled by Core layer'
    )]
    [CmdletBinding()]
    [OutputType([long])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Operation,

        [Parameter()]
        [string]$Details,

        [Parameter()]
        [string]$ConnectionString = (Get-StoreConnectionString)
    )

    process {
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

            $performedAt = [DateTime]::UtcNow.ToString('o')
            $performedBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

            $command.CommandText = @"
                INSERT INTO audit_log (
                    operation,
                    details,
                    performed_at,
                    performed_by
                ) VALUES (
                    @operation,
                    @details,
                    @performedAt,
                    @performedBy
                );
"@

            $null = $command.Parameters.Add('@operation',  [System.Data.DbType]::String).Value = $Operation
            $null = $command.Parameters.Add('@details',    [System.Data.DbType]::String).Value = $Details
            $null = $command.Parameters.Add('@performedAt',[System.Data.DbType]::String).Value = $performedAt
            $null = $command.Parameters.Add('@performedBy',[System.Data.DbType]::String).Value = $performedBy

            $null = $command.ExecuteNonQuery()

            $command.CommandText = "SELECT last_insert_rowid();"
            $result = $command.ExecuteScalar()

            $transaction.Commit()

            return [long]$result
        } catch {
            if ($transaction) {
                try {
                    $transaction.Rollback()
                } catch {
                    Write-Warning -Message "Transaction rollback failed: $($_.Exception.Message)"
                }
            }

            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'AuditInsertFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $Operation
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
