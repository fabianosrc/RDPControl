<#
.SYNOPSIS
Locates a validated binary signature within a Portable Executable (PE) byte array.

.DESCRIPTION
Searches a PE binary for a predefined core byte sequence and validates each
candidate against semantic context windows before and after the match.

This validation strategy helps reduce false positives by ensuring the matched
sequence is surrounded by expected instruction patterns.

The function returns a structured object describing the located signature,
replacement metadata, contextual byte windows, and validation statistics.

.PARAMETER Bytes
Byte array representing the Portable Executable (PE) content.

Accepts pipeline input by property name and is compatible with objects
returned by Import-PEFile.

.EXAMPLE
PS C:\> $pe = Import-PEFile -Path "$env:SystemRoot\System32\example.dll"
PS C:\> Find-BinarySignature -Bytes $pe.Bytes

.EXAMPLE
PS C:\> Import-PEFile -Path ".\example.dll" | Find-BinarySignature -Verbose

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
- DiscardedMatches  [int]

.NOTES
This function performs bounded byte inspection and semantic validation
against predefined binary patterns.

It does not modify the source binary.
#>
function Find-BinarySignature {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Bytes
    )

    begin {
        # Core byte sequence
        [byte[]]$corePattern = 0x39, 0x81, 0x3C, 0x06, 0x00, 0x00

        [int]$beforeWindowSize = 6
        [int]$afterWindowSize  = 6
        [int]$coreSize         = $corePattern.Length
    }

    process {
        try {
            if ($Bytes.Length -lt ($beforeWindowSize + $coreSize + $afterWindowSize)) {
                $ex = [System.IO.InvalidDataException]::new(
                    "The provided byte array is too small for signature analysis."
                )

                $err = [System.Management.Automation.ErrorRecord]::new(
                    $ex,
                    "BinaryTooSmall",
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $Bytes
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            [int]$discardedMatches = 0
            [int]$searchLimit      = $Bytes.Length - $coreSize

            Write-Verbose -Message ("Searching {0} bytes for binary signature..." -f $Bytes.Length)

            for ([int]$i = 0; $i -le $searchLimit; $i++) {
                # Prevent out-of-bounds access
                if (($i - $beforeWindowSize) -lt 0) {
                    continue
                }

                if (($i + $coreSize + $afterWindowSize) -gt $Bytes.Length) {
                    continue
                }

                # Step 1 - locate core sequence
                if (-not (Test-ByteSequence -Source $Bytes -Offset $i -Expected $corePattern)) {
                    continue
                }

                Write-Verbose -Message ("Candidate signature detected at offset 0x{0:X8}" -f $i)

                # Step 2 - validate preceding instruction context
                $beforeInstruction = Get-BeforeInstruction -Bytes $Bytes -CoreIndex $i

                if ($null -eq $beforeInstruction) {
                    Write-Verbose -Message "Context validation failed (preceding window)."
                    $discardedMatches++
                    continue
                }

                Write-Verbose -Message "Preceding context validated successfully."

                # Step 3 - validate following branch instruction
                [string]$branchType = Get-AsmJumpType -Bytes $Bytes -CoreIndex $i -CoreSize $coreSize

                if ($branchType -eq 'unknown') {
                    Write-Verbose -Message "Context validation failed (following branch)."
                    $discardedMatches++
                    continue
                }

                Write-Verbose -Message ("Branch instruction identified: {0}" -f $branchType)

                # Step 4 - derive replacement bytes dynamically
                $replacementParams = @{
                    ModRM        = $beforeInstruction.ModRM
                    Displacement = $beforeInstruction.Displacement
                    JumpType     = $branchType
                }

                [byte[]]$replacementBytes = New-ReplacementBytes @replacementParams

                Write-Verbose -Message "Replacement sequence generated successfully."

                # Step 5 - determine write offset based on branch context
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
                    ContextBefore    = Get-ByteWindow -Bytes $Bytes -Start ($i - $beforeWindowSize) -Length $beforeWindowSize
                    ContextAfter     = Get-ByteWindow -Bytes $Bytes -Start ($i + $coreSize) -Length $afterWindowSize
                    DiscardedMatches = $discardedMatches
                }
            }

            Write-Verbose -Message ("No validated signature was identified. Discarded matches: {0}" -f $discardedMatches)

            return [PSCustomObject]@{
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
                DiscardedMatches = $discardedMatches
            }
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                "BinarySignatureSearchFailed",
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $Bytes
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
