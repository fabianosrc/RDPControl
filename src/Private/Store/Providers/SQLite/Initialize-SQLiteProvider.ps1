<#
.SYNOPSIS
Initializes the SQLite database schema.

.DESCRIPTION
Creates the SQLite database and all required tables.
Safe to call multiple times - uses CREATE TABLE IF NOT EXISTS.

.OUTPUTS
None
#>
function Initialize-SQLiteProvider {
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    process {
        $connection = $null

        try {
            $connection = [System.Data.SQLite.SQLiteConnection]::new((Get-StoreConnectionString))

            $connection.Open()

            $command = $connection.CreateCommand()
            $command.CommandText = @"
                CREATE TABLE IF NOT EXISTS snapshots (
                    id             INTEGER PRIMARY KEY AUTOINCREMENT,
                    binary_path    TEXT    NOT NULL,
                    binary_version TEXT    NOT NULL,
                    os_build       TEXT    NOT NULL,
                    sha256         TEXT    NOT NULL UNIQUE,
                    enforced       INTEGER NOT NULL DEFAULT 0,
                    binary_blob    BLOB    NOT NULL,
                    created_at     TEXT    NOT NULL
                );

                CREATE TABLE IF NOT EXISTS audit_log (
                    id           INTEGER PRIMARY KEY AUTOINCREMENT,
                    operation    TEXT    NOT NULL,
                    details      TEXT,
                    performed_at TEXT    NOT NULL,
                    performed_by TEXT    NOT NULL
                );
"@

            [void]$command.ExecuteNonQuery()

            Write-Verbose 'SQLite schema initialized successfully.'
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'SQLiteInitializationFailed',
                    [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                    'SQLite store'
                )
            )
        } finally {
            if ($null -eq $connection) {
                $connection.Close()
                $connection.Dispose()
            }
        }
    }
}
