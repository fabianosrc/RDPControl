<#
.SYNOPSIS
Locates a validated binary signature within a Portable Executable (PE) byte array.

.DESCRIPTION
Searches a PE binary for a predefined core byte sequence and validates each
candidate against semantic context windows before and after the match.

This validation strategy helps reduce false positives by ensuring the matched
sequence is surrounded by expected instruction patterns.

Uses Array.IndexOf for fast native scanning instead of byte-by-byte iteration,
significantly reducing search time on large binaries.

The search logic runs in the end block to ensure it executes exactly once,
regardless of how the input is provided.

.PARAMETER Bytes
Byte array representing the Portable Executable (PE) content.

.EXAMPLE
PS C:\> $pe = Read-PEFile -Path "$env:SystemRoot\System32\example.dll"
PS C:\> Find-BinarySignature -Bytes $pe.Bytes

.EXAMPLE
PS C:\> Read-PEFile -Path ".\example.dll" | Find-BinarySignature -Verbose

.INPUTS
System.Byte[]

.OUTPUTS
System.Management.Automation.PSCustomObject

Returns an object with the following properties:

- Found             [bool]
- SignatureIndex    [int]
- SignatureOffset   [string]
- WriteIndex        [int]
- WriteOffset       [string]
- BranchType        [string]
- ReplacementBytes  [byte[]]
- ReplacementHex    [string]
- ContextBefore     [byte[]]
- ContextAfter      [byte[]]
- CurrentBytes      [byte[]]
- DiscardedMatches  [int]

.NOTES
This function performs bounded byte inspection and semantic validation
against predefined binary patterns.

It does not modify the source binary.
#>
function Find-BinarySignature {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Bytes
    )

    begin {
        # Core byte sequence to locate
        [byte[]]$corePattern = 0x39, 0x81, 0x3C, 0x06, 0x00, 0x00

        [int]$beforeWindowSize = 6
        [int]$afterWindowSize  = 6
        [int]$coreSize         = $corePattern.Length

        # Pre-filter bytes for fast Array.IndexOf scanning
        [byte]$firstByte  = $corePattern[0]
        [byte]$secondByte = $corePattern[1]
    }

    end {
        try {
            if ($Bytes.Length -lt ($beforeWindowSize + $coreSize + $afterWindowSize)) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.IO.InvalidDataException]::new(
                            'The provided byte array is too small for signature analysis.'
                        ),
                        'BinaryTooSmall',
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        $Bytes
                    )
                )
            }

            [int]$discardedMatches = 0
            [int]$searchLimit      = $Bytes.Length - $coreSize - $afterWindowSize
            [int]$i                = $beforeWindowSize

            Write-Verbose -Message ("Searching {0} bytes for binary signature..." -f $Bytes.Length)

            while ($i -le $searchLimit) {

                # Fast scan: native Array.IndexOf to find next first byte
                $i = [Array]::IndexOf($Bytes, $firstByte, $i, ($searchLimit - $i + 1))

                if ($i -lt 0) {
                    break
                }

                # Quick pre-filter: check second byte before full sequence check
                if ($Bytes[$i + 1] -ne $secondByte) {
                    $i++
                    continue
                }

                # Full core sequence validation
                if (-not (Test-ByteSequence -Source $Bytes -Offset $i -Expected $corePattern)) {
                    $i++
                    continue
                }

                Write-Verbose -Message ("Candidate signature detected at offset 0x{0:X8}" -f $i)

                # Validate preceding instruction context
                $beforeInstruction = Get-BeforeInstruction -Bytes $Bytes -ReferenceIndex $i

                if ($null -eq $beforeInstruction) {
                    Write-Verbose -Message 'Context validation failed (preceding window).'
                    $discardedMatches++
                    $i++
                    continue
                }

                Write-Verbose -Message 'Preceding context validated successfully.'

                # Validate following branch instruction
                $branchParams = @{
                    Bytes           = $Bytes
                    ReferenceIndex  = $i
                    ReferenceLength = $coreSize
                }

                [string]$branchType = Get-BranchType @branchParams

                if ($branchType -eq 'Unknown') {
                    Write-Verbose -Message 'Context validation failed (following branch).'
                    $discardedMatches++
                    $i++
                    continue
                }

                Write-Verbose -Message ("Branch instruction identified: {0}" -f $branchType)

                # Derive replacement bytes dynamically
                $replacementParams = @{
                    ModRM        = $beforeInstruction.ModRM
                    Displacement = $beforeInstruction.Displacement
                    JumpType     = $branchType
                }

                [byte[]]$replacementBytes = New-ReplacementByte @replacementParams

                Write-Verbose -Message 'Replacement sequence generated successfully.'

                [int]$writeIndex = if ($branchType -eq 'jne') {
                    $i - $beforeWindowSize
                } else {
                    $i
                }

                return [PSCustomObject]@{
                    PSTypeName       = 'RDPControl.BinarySignature'
                    Found            = $true
                    SignatureIndex   = $i
                    SignatureOffset  = '0x{0:X8}' -f $i
                    WriteIndex       = $writeIndex
                    WriteOffset      = '0x{0:X8}' -f $writeIndex
                    BranchType       = $branchType
                    ReplacementBytes = $replacementBytes
                    ReplacementHex   = [string]::Join(' ', ($replacementBytes | ForEach-Object { $_.ToString('X2') }))
                    ContextBefore    = Get-ByteRange -Bytes $Bytes -Start ($i - $beforeWindowSize) -Length $beforeWindowSize
                    ContextAfter     = Get-ByteRange -Bytes $Bytes -Start ($i + $coreSize) -Length $afterWindowSize
                    CurrentBytes     = Get-ByteRange -Bytes $Bytes -Start $i -Length ($coreSize + $afterWindowSize)
                    DiscardedMatches = $discardedMatches
                }
            }

            Write-Verbose -Message ("No validated signature identified. Discarded matches: {0}" -f $discardedMatches)

            [pscustomobject]@{
                PSTypeName       = 'RDPControl.BinarySignature'
                Found            = $false
                SignatureIndex   = -1
                SignatureOffset  = $null
                WriteIndex       = -1
                WriteOffset      = $null
                BranchType       = $null
                ReplacementBytes = $null
                ReplacementHex   = $null
                ContextBefore    = $null
                ContextAfter     = $null
                CurrentBytes     = $null
                DiscardedMatches = $discardedMatches
            }
        } catch {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $PSCmdlet.ThrowTerminatingError($_)
            }

            throw
        }
    }
}
