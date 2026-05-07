<#
.SYNOPSIS
Returns $true if the Expected byte sequence exists at the given Offset within Source.

.PARAMETER Source
Source byte array to search within.

.PARAMETER Offset
Zero-based index in Source where comparison starts.

.PARAMETER Expected
Byte sequence to match against.

.EXAMPLE
PS C:\> Test-ByteSequence -Source $bytes -Offset 0 -Expected @(0x39, 0x81)

.OUTPUTS
System.Boolean
#>
function Test-ByteSequence {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Source,

        [Parameter(Mandatory)]
        [int]$Offset,

        [Parameter(Mandatory)]
        [byte[]]$Expected
    )

    if ($Offset -lt 0 -or ($Offset + $Expected.Length) -gt $Source.Length) {
        return $false
    }

    for ([int]$i = 0; $i -lt $Expected.Length; $i++) {
        if ($Source[$Offset + $i] -ne $Expected[$i]) {
            return $false
        }
    }

    $true
}
