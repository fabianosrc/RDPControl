<#
.SYNOPSIS
Writes a complete byte array to a binary file, replacing its entire content.

.DESCRIPTION
Replaces the full content of a binary file using a single atomic write
operation via System.IO.File.WriteAllBytes.

This function is intended for full-file restoration scenarios where the
entire binary must be replaced from a stored snapshot blob.

For partial in-place writes at a specific offset, use Write-BinaryByte.

.PARAMETER Path
Full path to the target binary file.

.PARAMETER Bytes
Complete byte array to write. Replaces the entire file content.

.EXAMPLE
PS C:\> Write-BinaryContent -Path '.\termsrv.dll' -Bytes $snapshotBlob

.INPUTS
None

.OUTPUTS
None

.NOTES
This function performs full binary replacement only.
It does not support partial writes, offset-based operations,
or file stream locking.
#>
function Write-BinaryContent {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Bytes
    )

    process {
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.IO.FileNotFoundException]::new(
                            'File not found.',
                            $Path
                        ),
                        'BinaryFileNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $Path
                    )
                )
            }

            $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath

            Write-Verbose -Message ("Writing {0} bytes to [{1}]." -f $Bytes.Length, $resolvedPath)

            [System.IO.File]::WriteAllBytes($resolvedPath, $Bytes)

            Write-Verbose -Message 'Binary content written successfully.'
        } catch {
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
