<#
.SYNOPSIS
Resolves the SQLite database path for the RDPControl store.

.DESCRIPTION
Reads the environment configuration file located in ProgramData and
returns the absolute path to the SQLite database file.

This function is part of the Store Core layer and is responsible for
resolving storage location independently of any provider implementation.

.EXAMPLE
PS C:\> Get-StoreDatabasePath
C:\ProgramData\RDPControl\store.db

.OUTPUTS
System.String
#>
function Get-StoreDatabasePath {
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    process {
        $envFile = Join-Path -Path $env:ProgramData -ChildPath 'RDPControl\environment.json'

        try {
            $config = Get-Content -LiteralPath $envFile -Raw -ErrorAction Stop | ConvertFrom-Json

            if ([string]::IsNullOrWhiteSpace($config.paths.DatabasePath)) {
                throw "Missing 'DatabasePath' in environment configuration."
            }

            $config.paths.DatabasePath
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'StoreDatabasePathResolutionFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $envFile
                )
            )
        }
    }
}
