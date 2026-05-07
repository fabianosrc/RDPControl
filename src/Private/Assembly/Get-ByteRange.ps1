<#
.SYNOPSIS
Extracts a byte range from a byte array.

.DESCRIPTION
Returns a new byte array containing the specified range extracted from
the source byte array.

The start position and requested length are validated against the
source array bounds.

Behavior rules:

    - Negative start values are clamped to 0
    - Start values beyond array bounds return an empty array
    - Length values extending beyond array bounds are truncated
    - Zero-length requests return an empty array

The source array is never modified.

.PARAMETER Bytes
Source byte array.

.PARAMETER Start
Zero-based starting index.

Negative values are automatically clamped to 0.

.PARAMETER Length
Number of bytes to extract.

.EXAMPLE
PS C:\> Get-ByteRange -Bytes $content -Start 100 -Length 6

.INPUTS
None

.OUTPUTS
System.Byte[]

.NOTES
This function performs non-destructive byte extraction only.
#>
function Get-ByteRange {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [int64]$Start,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Length
    )

    process {
        if ($Bytes.Length -eq 0) {
            return [byte[]]::new(0)
        }

        if ($Length -eq 0) {
            return [byte[]]::new(0)
        }

        [Int64]$effectiveStart = [Math]::Max(0, $Start)

        if ($effectiveStart -ge $Bytes.Length) {
            return [byte[]]::new(0)
        }

        [Int64]$availableLength = $Bytes.Length - $effectiveStart

        [int]$effectiveLength = [Math]::Min($Length, $availableLength)

        if ($effectiveLength -le 0) {
            return [byte[]]::new(0)
        }

        [byte[]]$result = [byte[]]::new($effectiveLength)

        [System.Array]::Copy(
            $Bytes,
            $effectiveStart,
            $result,
            0,
            $effectiveLength
        )

        return $result
    }
}
