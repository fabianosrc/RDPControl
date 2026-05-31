<#
.SYNOPSIS
Writes a complete byte array to a binary file, replacing its entire content.

.DESCRIPTION
Resolves the target path, validates that it refers to a file (not a directory),
validates the byte array, and writes the content using WriteAllBytes.

This function is intended for internal engine use only.

.PARAMETER Path
Full path to the target binary file.

.PARAMETER Bytes
Byte array to write. Must not be null or empty.

.EXAMPLE
PS C:\> Write-BinaryContent -Path 'C:\Path\To\Example.dll' -Bytes $bytes

.INPUTS
None

.OUTPUTS
None
#>
function Write-BinaryContent {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    process {
        try {
            # -----------------------------
            # Check existence first
            # -----------------------------
            if (-not (Test-Path -LiteralPath $Path)) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("File not found: $Path"),
                        'BinaryFileNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $Path
                    )
                )
            }

            # -----------------------------
            # Resolve path first (canonical)
            # -----------------------------
            $resolvedPath = Resolve-Path -LiteralPath $Path
            $fullPath     = $resolvedPath.ProviderPath

            # -----------------------------
            # Directory validation
            # -----------------------------
            if (Test-Path -LiteralPath $fullPath -PathType Container) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Path is a directory: $fullPath"),
                        'BinaryPathIsDirectory',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $fullPath
                    )
                )
            }

            # -----------------------------
            # Bytes validation (explicit, predictable)
            # -----------------------------
            if ($null -eq $Bytes -or $Bytes.Count -eq 0) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Bytes cannot be null or empty'),
                        'BinaryBytesEmpty',
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        $fullPath
                    )
                )
            }

            # -----------------------------
            # Write operation
            # -----------------------------
            Write-Verbose -Message ("Writing {0} bytes to [{1}]." -f $Bytes.Count, $fullPath)

            [System.IO.File]::WriteAllBytes($fullPath, $Bytes)

            Write-Verbose -Message 'Binary content written successfully.'
        } catch {
            # -----------------------------
            # File Not Found (TESTABLE)
            # -----------------------------
            if ($_.FullyQualifiedErrorId -eq 'PathNotFound') {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("File not found: $Path"),
                        'BinaryFileNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $Path
                    )
                )
            }

            # -----------------------------
            # Unexpected IO / system failures
            # -----------------------------
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'BinaryContentWriteFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $Path
                )
            )
        }
    }
}
