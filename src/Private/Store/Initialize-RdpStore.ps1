<#
.SYNOPSIS
Creates the RDPControl SQLite database and schema.

.DESCRIPTION
Creates the SQLite database file and all required tables using the database
path from the initialized environment. Safe to call multiple times - uses
CREATE TABLE IF NOT EXISTS for idempotency.

Tables created:
    snapshots - stores binary blobs with version and hash metadata
    audit_log - records all module operations for traceability

.EXAMPLE
PS C:\> Initialize-RdpStore

.OUTPUTS
None
#>
function Initialize-RdpStore {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param ()

    begin {
        Assert-RdpEnvironment

        $env    = Get-RdpEnvironment -Strict
        $dbPath = Join-Path -Path $env.DatabasePath -ChildPath 'rdpcontrol.db'

        Write-Verbose -Message "Target database: $dbPath"
    }

    process {
        if (-not $PSCmdlet.ShouldProcess($dbPath, 'Initialize SQLite schema')) {
            return
        }

        $connection = $null

        try {
            $connection = [System.Data.SQLite.SQLiteConnection]::new(
                "Data Source=$dbPath;Version=3;"
            )

            $connection.Open()

            $command = $connection.CreateCommand()
            $command.CommandText = @"
                CREATE TABLE IF NOT EXISTS snapshots (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    dll_path    TEXT    NOT NULL,
                    dll_version TEXT    NOT NULL,
                    os_build    TEXT    NOT NULL,
                    sha256      TEXT    NOT NULL UNIQUE,
                    enforced    INTEGER NOT NULL DEFAULT 0,
                    created_at  TEXT    NOT NULL,
                    blob        BLOB    NOT NULL
                );

                CREATE TABLE IF NOT EXISTS audit_log (
                    id           INTEGER PRIMARY KEY AUTOINCREMENT,
                    operation    TEXT    NOT NULL,
                    details      TEXT,
                    performed_at TEXT    NOT NULL,
                    performed_by TEXT    NOT NULL
                );
"@
            $null = $command.ExecuteNonQuery()

            Write-Verbose -Message 'SQLite schema initialized successfully.'
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'StoreInitializationFailed',
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
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
