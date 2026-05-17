<#
.SYNOPSIS
Determines the target architecture of a Portable Executable (PE) file.

.DESCRIPTION
Reads the PE Optional Header magic value from a binary to determine whether
the file targets x86 (PE32), x64 (PE32+), or ROM images.

Supports input as a byte array or from a file path. Includes validation of
DOS header (MZ) and PE signature (PE\0\0) to ensure the file is a valid PE.

Typed exceptions propagate naturally without generic wrapping:
    - System.IO.InvalidDataException       - malformed or truncated PE data
    - System.IO.FileNotFoundException      - file not found
    - System.IO.IOException                - file access errors
    - System.UnauthorizedAccessException   - insufficient permissions
    - System.PlatformNotSupportedException - big-endian systems

.PARAMETER Bytes
Byte array representing the binary content of a PE file.

.PARAMETER Path
Path to a PE file on disk. Opened with FileShare.ReadWrite to allow
reading binaries currently in use by the operating system.

.INPUTS
None

.OUTPUTS
System.String

Returns:
    'x86' for PE32   (magic 0x10B)
    'x64' for PE32+  (magic 0x20B)
    'ROM' for ROM    (magic 0x107)

.EXAMPLE
PS C:\> Get-PEArchitecture -Path "$env:SystemRoot\System32\notepad.exe"
x64

.EXAMPLE
PS C:\> $bytes = [System.IO.File]::ReadAllBytes('C:\test.exe')
PS C:\> Get-PEArchitecture -Bytes $bytes
x86

.NOTES
Compatible with Windows PowerShell 5.1+.
Performs minimal PE parsing - does not fully parse the PE structure.
#>
function Get-PEArchitecture {
    [CmdletBinding(DefaultParameterSetName = 'Bytes')]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Bytes')]
        [AllowEmptyCollection()]
        [ValidateNotNull()]
        [byte[]]$Bytes,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNull()]
        [string]$Path
    )

    begin {
        if (-not [System.BitConverter]::IsLittleEndian) {
            throw [System.PlatformNotSupportedException]::new(
                'Big-endian systems are not supported.'
            )
        }

        # PE structure size constants
        [int]$DosHeaderMinSize  = 64
        [int]$PeSigSize         = 4
        [int]$CoffHeaderSize    = 20
        [int]$OptionalMagicSize = 2
        [int]$PeHeaderMinBytes  = $PeSigSize + $CoffHeaderSize + $OptionalMagicSize
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $stream = $null

            try {
                $stream = [System.IO.File]::Open(
                    $Path,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite
                )

                if ($stream.Length -gt [int]::MaxValue) {
                    throw [System.IO.InvalidDataException]::new(
                        'PE image is too large to process.'
                    )
                }

                $Bytes        = [byte[]]::new($stream.Length)
                $bytesRead    = $stream.Read($Bytes, 0, $Bytes.Length)

                if ($bytesRead -ne $Bytes.Length) {
                    throw [System.IO.IOException]::new(
                        'Failed to read the complete PE image from disk.'
                    )
                }
            } catch [System.Management.Automation.MethodInvocationException] {
                # Unwrap MethodInvocationException to expose the original
                # typed .NET exception (e.g. FileNotFoundException)
                throw $_.Exception.InnerException
            } finally {
                if ($null -ne $stream) {
                    $stream.Dispose()
                }
            }
        }

        if ($Bytes.Length -eq 0) {
            throw [System.IO.InvalidDataException]::new(
                'PE image buffer cannot be empty.'
            )
        }

        if ($Bytes.Length -lt $DosHeaderMinSize) {
            throw [System.IO.InvalidDataException]::new(
                'PE image buffer is too small to contain a valid DOS header.'
            )
        }

        # Validate DOS header (MZ)
        if ($Bytes[0] -ne 0x4D -or $Bytes[1] -ne 0x5A) {
            throw [System.IO.InvalidDataException]::new(
                'Missing DOS header signature (MZ).'
            )
        }

        [UInt32]$e_lfanew = [System.BitConverter]::ToUInt32($Bytes, 0x3C)

        if (($e_lfanew + $PeHeaderMinBytes) -gt $Bytes.Length) {
            throw [System.IO.InvalidDataException]::new(
                'Invalid PE header offset.'
            )
        }

        # Validate PE signature (PE\0\0)
        if ($Bytes[$e_lfanew]     -ne 0x50 -or
            $Bytes[$e_lfanew + 1] -ne 0x45 -or
            $Bytes[$e_lfanew + 2] -ne 0x00 -or
            $Bytes[$e_lfanew + 3] -ne 0x00) {
            throw [System.IO.InvalidDataException]::new(
                'Missing PE signature (PE\0\0).'
            )
        }

        [int]$optionalHeaderOffset = $e_lfanew + $PeSigSize + $CoffHeaderSize
        [UInt16]$magic             = [System.BitConverter]::ToUInt16($Bytes, $optionalHeaderOffset)

        switch ($magic) {
            0x10B { return 'x86' }
            0x20B { return 'x64' }
            0x107 { return 'ROM' }
            default {
                throw [System.IO.InvalidDataException]::new(
                    "Unknown PE optional header magic value: 0x{0:X4}." -f $magic
                )
            }
        }
    }
}
