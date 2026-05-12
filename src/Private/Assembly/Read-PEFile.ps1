<#
.SYNOPSIS
Reads a binary file into memory and returns its bytes with architecture metadata.

.DESCRIPTION
Reads the specified file into a byte array using System.IO.File.ReadAllBytes,
then inspects the PE header to determine the target architecture (x86 or x64).

Returns a PSCustomObject containing both the raw bytes and the detected
architecture, allowing callers to validate compatibility before processing.

.PARAMETER Path
Full path to the binary file.

.EXAMPLE
$assembly = Read-PEFile -Path "$env:SystemRoot\System32\notepad.exe"
Write-Output "Architecture: $($assembly.Architecture)"
Write-Output "Size: $($assembly.Bytes.Length) bytes"

.OUTPUTS
PSCustomObject with:
Bytes        [byte[]] - raw file content
Architecture [string] - 'x86' or 'x64'
Path         [string] - resolved full path
#>
function Read-PEFile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process {
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                throw [System.IO.FileNotFoundException]::new("File not found.", $Path)
            }

            $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath

            Write-Verbose "Reading binary: $resolvedPath"

            [byte[]]$bytes = [System.IO.File]::ReadAllBytes($resolvedPath)

            Write-Verbose "Read $($bytes.Length) bytes."

            $architecture = Get-PEArchitecture -Bytes $bytes

            Write-Verbose "Detected architecture: $architecture"

            $obj = [PSCustomObject]@{
                PSTypeName   = 'RDPControl.PEFile'
                Bytes        = $bytes
                Architecture = $architecture
                Path         = $resolvedPath
            }

            return $obj
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                "ReadPEFileFailed",
                [System.Management.Automation.ErrorCategory]::ReadError,
                $Path
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
