<#
.SYNOPSIS
Initializes the RDPControl environment.

.DESCRIPTION
Creates the required directory structure and environment file under ProgramData.
Must be run once before using any other RDPControl cmdlet.

The environment is stored at: $env:ProgramData\RDPControl\

Directory structure created:
    data\        - reserved for future use
    database\    - SQLite database
    logs\        - operation logs
    policy\      - policy state files

Behavior:
    (default) - Initializes only if environment does not exist.
                Errors if already initialized.

    -Force    - Recreates missing directories and files.
                Preserves existing data.

    -Purge    - Removes everything and reinitializes from scratch.
                Requires confirmation.

.PARAMETER Force
Recreates missing components without affecting existing data.

.PARAMETER Purge
Removes the entire environment and reinitializes.

.EXAMPLE
PS C:\> Initialize-RdpEnvironment

.EXAMPLE
PS C:\> Initialize-RdpEnvironment -Force

.EXAMPLE
PS C:\> Initialize-RdpEnvironment -Purge

.OUTPUTS
PSCustomObject
#>
function Initialize-RdpEnvironment {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Default')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(ParameterSetName = 'Force')]
        [switch]$Force,

        [Parameter(ParameterSetName = 'Purge')]
        [switch]$Purge
    )

    begin {
        if (-not (Test-IsElevated)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new(
                        'Initialize-RdpEnvironment requires elevated privileges. ' +
                        'Run PowerShell as Administrator.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }
    }

    process {
        $basePath    = Join-Path -Path $env:ProgramData -ChildPath 'RDPControl'
        $envFile     = Join-Path -Path $basePath -ChildPath 'environment.json'
        $dbDirectory = Join-Path -Path $basePath -ChildPath 'database'

        $directories = [ordered]@{
            BasePath     = $basePath
            DatabasePath = $dbDirectory
            DatabaseFile = Join-Path -Path $dbDirectory -ChildPath 'rdpcontrol.db'
            LogPath      = Join-Path -Path $basePath -ChildPath 'logs'
            PolicyPath   = Join-Path -Path $basePath -ChildPath 'policy'
            DataPath     = Join-Path -Path $basePath -ChildPath 'data'
        }

        # Default mode: block if already initialized
        if ($PSCmdlet.ParameterSetName -eq 'Default' -and (Test-Path -LiteralPath $envFile -PathType Leaf)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        "RDPControl environment already exists at [$basePath]. " +
                        'Use -Force to repair or -Purge to reset.'
                    ),
                    'EnvironmentAlreadyExists',
                    [System.Management.Automation.ErrorCategory]::ResourceExists,
                    $basePath
                )
            )
        }

        # Force mode: log intent explicitly to satisfy PSScriptAnalyzer
        if ($Force) {
            Write-Verbose -Message 'Force mode: recreating missing components.'
        }

        # Purge mode: remove and reinitialize
        if ($Purge) {
            if (-not $PSCmdlet.ShouldProcess($basePath, 'Remove entire RDPControl environment and reinitialize')) {
                return
            }

            if (Test-Path -LiteralPath $basePath -PathType Container) {
                Remove-Item -LiteralPath $basePath -Recurse -Force -ErrorAction Stop
                Write-Verbose -Message "Environment purged: $basePath"
            }
        }

        # Create required directories (skip DatabaseFile - it is a file path, not a directory)
        $directoriesToCreate = $directories.GetEnumerator() |
            Where-Object -FilterScript { $_.Key -ne 'DatabaseFile' }

        foreach ($entry in $directoriesToCreate) {
            if (-not (Test-Path -LiteralPath $entry.Value -PathType Container)) {
                New-Item -Path $entry.Value -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Write-Verbose -Message "Created directory: $($entry.Value)"
            }
        }

        try {
            $moduleVersion = $MyInvocation.MyCommand.Module.Version.ToString()

            $environment = [ordered]@{
                version     = $moduleVersion
                createdAt   = (Get-Date).ToUniversalTime().ToString('o')
                machine     = $env:COMPUTERNAME
                performedBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                paths       = $directories
            }

            $environment |
                ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath $envFile -Encoding UTF8 -ErrorAction Stop
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        "Failed to create environment configuration. $_"
                    ),
                    'EnvironmentWriteFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $envFile
                )
            )
        }

        Write-Verbose -Message "RDPControl environment initialized at: $basePath"

        # Initialize SQLite database schema before emitting output
        Initialize-RdpStore

        [PSCustomObject]@{
            BasePath     = $directories.BasePath
            DatabasePath = $directories.DatabasePath
            DatabaseFile = $directories.DatabaseFile
            LogPath      = $directories.LogPath
            PolicyPath   = $directories.PolicyPath
            DataPath     = $directories.DataPath
            Environment  = $envFile
            CreatedAt    = $environment.createdAt
            Version      = $environment.version
        }
    }
}
