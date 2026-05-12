<#
.SYNOPSIS
Returns the SQLite connection string for the RDPControl store.

.DESCRIPTION
Builds a SQLite connection string using the database path resolved by
Get-StoreDatabasePath.

This function does not perform any file system or configuration parsing
directly, maintaining separation of concerns within the Store Core layer.

.EXAMPLE
PS C:\> Get-StoreConnectionString
Data Source=C:\ProgramData\RDPControl\store.db;Version=3;

.OUTPUTS
System.String
#>
function Get-StoreConnectionString {
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    process {
        $databaseFile = $Script:Environment.paths.DatabaseFile

        if ([string]::IsNullOrWhiteSpace($databaseFile)) {
            throw 'Database file path is null or empty.'
        }

        $databaseDirectory = Split-Path -Path $databaseFile -Parent

        if (-not (Test-Path -LiteralPath $databaseDirectory -PathType Container)) {
            throw (
                "Database directory does not exist: " +
                "$databaseDirectory"
            )
        }

        "Data Source=$databaseFile;Version=3;"
    }
}
