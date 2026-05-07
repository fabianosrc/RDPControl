<#
.SYNOPSIS
Determines the target architecture of a Portable Executable (PE) file.

.DESCRIPTION
Reads the PE Optional Header magic value from a binary to determine whether
the file targets x86 (PE32), x64 (PE32+), or ROM images.

Supports input as a byte array or from a file path. Includes validation of
DOS header (MZ) and PE signature (PE\0\0) to ensure the file is a valid PE.

.PARAMETER Bytes
Byte array representing the binary content of a PE file.

.PARAMETER Path
Path to a file on disk. The file will be read as a byte array.

.INPUTS
System.Byte[]
System.String

You can pipe a byte array or a file path to this function.

.OUTPUTS
System.String

Returns:
- 'x86' for PE32
- 'x64' for PE32+
- 'ROM' for ROM images

.EXAMPLE
PS C:\> Get-PEArchitecture -Path "$env:SystemRoot\System32\notepad.exe"
x64

.EXAMPLE
PS C:\> [System.IO.File]::ReadAllBytes("C:\test.exe") | Get-PEArchitecture
x86

.NOTES
Compatible with Windows PowerShell 5.1+.
Performs minimal PE parsing and does not fully parse the PE structure.
#>
function Get-PEArchitecture {
    [CmdletBinding(DefaultParameterSetName = 'Bytes')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Bytes', ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Bytes,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
                throw "File not found: $_"
            }
            $true
        })]
        [string]$Path
    )

    begin {
        if (-not [System.BitConverter]::IsLittleEndian) {
            $ex = [System.PlatformNotSupportedException]::new(
                "Big-endian systems are not supported."
            )

            $err = [System.Management.Automation.ErrorRecord]::new(
                $ex,
                "UnsupportedPlatform",
                [System.Management.Automation.ErrorCategory]::NotImplemented,
                $null
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }

    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Bytes = [System.IO.File]::ReadAllBytes($Path)
            }

            if ($Bytes.Length -lt 64) {
                throw [System.IO.InvalidDataException]::new(
                    "File is too small to be a valid PE."
                )
            }

            # Validate DOS header (MZ)
            if ($Bytes[0] -ne 0x4D -or $Bytes[1] -ne 0x5A) {
                throw [System.IO.InvalidDataException]::new(
                    "Missing DOS header signature (MZ)."
                )
            }

            $e_lfanew = [System.BitConverter]::ToInt32($Bytes, 0x3C)

            if ($e_lfanew -lt 0 -or ($e_lfanew + 26) -gt $Bytes.Length) {
                throw [System.IO.InvalidDataException]::new(
                    "Invalid PE header offset."
                )
            }

            # Validate PE signature (PE\0\0)
            if ($Bytes[$e_lfanew]     -ne 0x50 -or
                $Bytes[$e_lfanew + 1] -ne 0x45 -or
                $Bytes[$e_lfanew + 2] -ne 0x00 -or
                $Bytes[$e_lfanew + 3] -ne 0x00) {
                throw [System.IO.InvalidDataException]::new(
                    "Missing PE signature (PE\0\0)."
                )
            }

            $optionalHeaderOffset = $e_lfanew + 24
            $magic = [System.BitConverter]::ToInt16($Bytes, $optionalHeaderOffset)

            switch ($magic) {
                0x10B { 'x86' }
                0x20B { 'x64' }
                0x107 { 'ROM' }
                default {
                    throw [System.NotSupportedException]::new(
                        "Unknown PE architecture. Magic: 0x$($magic.ToString('X4'))"
                    )
                }
            }
        } catch {
            $target = if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Path
            } else {
                $Bytes
            }

            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                "PEArchitectureDetectionFailed",
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $target
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
