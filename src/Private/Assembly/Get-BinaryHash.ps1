<#
.SYNOPSIS
Computes the SHA256 hash of a byte array.

.DESCRIPTION
Computes the SHA256 hash of the provided byte array using
System.Security.Cryptography.SHA256.

The resulting hash is returned as an uppercase hexadecimal string
without separators, suitable for:
    - Integrity validation
    - Binary identification
    - Logging
    - Comparison operations
    - Catalog indexing

.PARAMETER Bytes
Byte array to hash.

.EXAMPLE
PS C:\> $pe = Read-PEFile -Path "$env:SystemRoot\System32\kernel32.dll"
PS C:\> Get-BinaryHash -Bytes $pe.Bytes

.EXAMPLE
PS C:\> $bytes = [System.IO.File]::ReadAllBytes('.\example.dll')
PS C:\> $hash = Get-BinaryHash -Bytes $bytes

.INPUTS
System.Byte[]

.OUTPUTS
System.String

Returns a 64-character uppercase SHA256 hexadecimal string.

.NOTES
This function hashes in-memory byte arrays only.
It does not perform file system operations.
#>
function Get-BinaryHash {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Bytes
    )

    process {
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

            Write-Verbose -Message ("Computing SHA256 hash for byte array ({0} bytes)." -f $Bytes.Length)

            $sha256 = [System.Security.Cryptography.SHA256]::Create()

            try {
                [byte[]]$hashBytes = $sha256.ComputeHash($Bytes)

                $builder = [System.Text.StringBuilder]::new(64)

                foreach ($byteValue in $hashBytes) {
                    [void]$builder.Append($byteValue.ToString('X2'))
                }

                [string]$hash = $builder.ToString()

                Write-Verbose -Message ("SHA256 hash computed successfully.")

                return $hash.ToLower()
            } finally {
                if ($null -ne $sha256) {
                    $sha256.Dispose()
                }
            }
        } catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                "BinaryHashComputationFailed",
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Bytes
            )

            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
}
