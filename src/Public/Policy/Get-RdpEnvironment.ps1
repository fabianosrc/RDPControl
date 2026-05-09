<#
.SYNOPSIS
Returns the current RDPControl environment configuration.

.DESCRIPTION
Reads and returns the environment.json file from the RDPControl
ProgramData directory.

Use -Strict to additionally validate that all required directories
and the database file exist.

.PARAMETER Strict
When specified, validates that all required directories and the
database file exist. Throws a terminating error if any required
component is missing.

.EXAMPLE
PS C:\> Get-RdpEnvironment

.EXAMPLE
PS C:\> Get-RdpEnvironment -Strict

.INPUTS
None

.OUTPUTS
PSCustomObject with properties:
    Version         [string]   - module version that created the environment
    CreatedAt       [datetime] - UTC timestamp of initialization
    Machine         [string]   - computer name
    PerformedBy     [string]   - user who initialized the environment
    BasePath        [string]   - root environment path
    DatabasePath    [string]   - SQLite database directory
    DatabaseFile    [string]   - SQLite database file path
    LogPath         [string]   - logs directory
    PolicyPath      [string]   - policy directory
    EnvironmentPath [string]   - environment file path
#>
function Get-RdpEnvironment {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [switch]$Strict
    )

    begin {
        Assert-RdpEnvironment
    }

    process {
        $environmentPath = Join-Path -Path $env:ProgramData -ChildPath 'RDPControl\environment.json'

        try {
            $raw = Get-Content -LiteralPath $environmentPath -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'EnvironmentReadFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $environmentPath
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }

        $result = [pscustomobject]@{
            Version         = $raw.version
            CreatedAt       = [datetime]$raw.createdAt
            Machine         = $raw.machine
            PerformedBy     = $raw.performedBy
            BasePath        = $raw.paths.BasePath
            DatabasePath    = $raw.paths.DatabasePath
            DatabaseFile    = $raw.paths.DatabaseFile
            LogPath         = $raw.paths.LogPath
            PolicyPath      = $raw.paths.PolicyPath
            EnvironmentPath = $environmentPath
        }

        if ($Strict) {
            $requiredDirectories = @(
                $result.BasePath
                $result.DatabasePath
                $result.LogPath
                $result.PolicyPath
            )

            foreach ($path in $requiredDirectories) {
                if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                    $err = [System.Management.Automation.ErrorRecord]::new(
                        [System.IO.DirectoryNotFoundException]::new(
                            "Required directory missing: [$path]. " +
                            'Run Initialize-RdpControl -Force to repair.'
                        ),
                        'EnvironmentCorrupted',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $path
                    )

                    $PSCmdlet.ThrowTerminatingError($err)
                }
            }

            if (-not (Test-Path -LiteralPath $result.DatabaseFile -PathType Leaf)) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new(
                        'Database file missing. ' +
                        'Run Initialize-RdpControl -Force to repair.',
                        $result.DatabaseFile
                    ),
                    'EnvironmentDatabaseMissing',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $result.DatabaseFile
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            Write-Verbose -Message 'RDPControl environment validation completed successfully.'
        }

        $result
    }
}
