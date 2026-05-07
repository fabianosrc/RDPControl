<#
.SYNOPSIS
Retrieves version metadata from a binary file.

.DESCRIPTION
Reads version information from a Portable Executable (PE) file using
System.Diagnostics.FileVersionInfo.

Returns both the original version strings exposed by the binary resource
metadata and a normalized System.Version object suitable for semantic
comparison operations.

.PARAMETER Path
Full path to the binary file.

.EXAMPLE
PS C:\> Get-BinaryVersion -Path "$env:SystemRoot\System32\kernel32.dll"

.EXAMPLE
PS C:\> $version = Get-BinaryVersion -Path ".\example.dll"
PS C:\> $version.FileVersion
PS C:\> $version.ProductVersion

.INPUTS
None

.OUTPUTS
System.Management.Automation.PSCustomObject

Returns an object with the following properties:

- Path               [string]
- FileVersion        [string]
- ProductVersion     [string]
- NormalizedVersion  [System.Version]

.NOTES
This function reads version resource metadata only.
It does not validate binary authenticity or integrity.
#>
function Get-BinaryVersion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process {
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                $exception = [System.IO.FileNotFoundException]::new(
                    "File not found.",
                    $Path
                )

                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    "BinaryFileNotFound",
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Path
                )

                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath

            Write-Verbose -Message ("Reading binary version metadata from [{0}]" -f $resolvedPath)

            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
                $resolvedPath
            )

            if ([string]::IsNullOrWhiteSpace($versionInfo.FileVersion) -and
                [string]::IsNullOrWhiteSpace($versionInfo.ProductVersion)
            ) {

                $exception = [System.InvalidOperationException]::new(
                    "Version metadata is not available for the specified binary."
                )

                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    "BinaryVersionMetadataUnavailable",
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $resolvedPath
                )

                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $normalizedVersion = [System.Version]::new(
                $versionInfo.FileMajorPart,
                $versionInfo.FileMinorPart,
                $versionInfo.FileBuildPart,
                $versionInfo.FilePrivatePart
            )

            Write-Verbose -Message ("FileVersion: {0}" -f $versionInfo.FileVersion)

            Write-Verbose -Message ("ProductVersion: {0}" -f $versionInfo.ProductVersion)

            return [PSCustomObject]@{
                PSTypeName        = 'RDPControl.BinaryVersion'
                Path              = $resolvedPath
                FileVersion       = $normalizedVersion.ToString()
                ProductVersion    = $versionInfo.ProductVersion
                NormalizedVersion = $normalizedVersion
            }
        } catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                "BinaryVersionReadFailed",
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $Path
            )

            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
}
