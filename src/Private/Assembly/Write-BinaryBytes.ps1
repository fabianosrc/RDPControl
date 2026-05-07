<#
.SYNOPSIS
Writes a byte sequence into a binary file at a specified offset.

.DESCRIPTION
Opens a binary file using an exclusive FileStream lock and writes the
provided byte sequence directly at the specified offset.

The function validates:
    - File existence
    - Offset boundaries
    - Byte array length
    - Write range integrity

Only the target byte region is overwritten. The original file size and
layout are preserved.

This is an internal binary IO primitive intended for controlled module
operations.

.PARAMETER Path
Full path to the target binary file.

.PARAMETER Offset
Zero-based byte offset where the write operation begins.

.PARAMETER Bytes
Byte sequence to write into the binary.

.EXAMPLE
PS C:\> Write-BinaryBytes -Path '.\example.dll' -Offset 512 -Bytes $bytes

.INPUTS
None

.OUTPUTS
System.Management.Automation.PSCustomObject

Returns an object with the following properties:

- Path    [string]
- Offset  [int64]
- Length  [int]
- Success [bool]

.NOTES
This function performs in-place binary writes only.
It does not resize, truncate, or rebuild the target file.
#>
function Write-BinaryBytes {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateRange(0, [Int64]::MaxValue)]
        [Int64]$Offset,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Bytes
    )

    process {
        $fileStream = $null

        try {
            if ($Bytes.Length -eq 0) {
                $exception = [System.ArgumentException]::new("Byte array cannot be empty.")

                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    "EmptyByteArray",
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $Bytes
                )

                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

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

            Write-Verbose -Message ("Opening binary file [{0}] with exclusive access." -f $resolvedPath)

            $fileStream = [System.IO.FileStream]::new(
                $resolvedPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )

            [int64]$fileLength = $fileStream.Length
            [int64]$endOffset  = $Offset + $Bytes.Length

            if ($endOffset -gt $fileLength) {
                $exception = [System.ArgumentOutOfRangeException]::new("Offset", (
                    "Write operation exceeds file bounds. " +
                    "Offset: {0}, Length: {1}, FileSize: {2}" -f
                    $Offset,
                    $Bytes.Length,
                    $fileLength
                ))

                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    "WriteOperationExceedsFileBounds",
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $resolvedPath
                )

                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            Write-Verbose -Message ("Seeking to offset 0x{0:X8}." -f $Offset)

            [void]$fileStream.Seek($Offset, [System.IO.SeekOrigin]::Begin)

            Write-Verbose -Message ("Writing {0} bytes." -f $Bytes.Length)

            $fileStream.Write($Bytes, 0, $Bytes.Length)

            $fileStream.Flush()

            Write-Verbose -Message "Binary write operation completed successfully."

            return [PSCustomObject]@{
                PSTypeName = 'RDPControl.BinaryWriteResult'
                Path       = $resolvedPath
                Offset     = $Offset
                Length     = $Bytes.Length
                Success    = $true
            }
        } catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                "BinaryWriteOperationFailed",
                [System.Management.Automation.ErrorCategory]::WriteError,
                $Path
            )

            $PSCmdlet.ThrowTerminatingError($errorRecord)
        } finally {
            if ($null -ne $fileStream) {
                Write-Verbose -Message "Closing file stream."
                $fileStream.Dispose()
            }
        }
    }
}
