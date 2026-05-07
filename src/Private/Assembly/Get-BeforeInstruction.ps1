<#
.SYNOPSIS
Validates the instruction immediately preceding a reference sequence and extracts instruction metadata.

.DESCRIPTION
Inspects the 6-byte region immediately preceding a reference sequence.

The function validates the presence of a compatible instruction layout
using the following structure:

    8B ?? 38 06 00 00

Where:

    8B
        Expected instruction opcode

    ??
        ModR/M byte

    38 06 00 00
        Expected displacement anchor

If validation succeeds, the function returns extracted instruction
metadata including the ModR/M byte and displacement bytes.

Returns $null when the preceding instruction does not match the
expected structure.

.PARAMETER Bytes
Byte array containing the binary content to inspect.

.PARAMETER ReferenceIndex
Byte index where the reference sequence begins.

.EXAMPLE
PS C:\> $context = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 0x1E815

.INPUTS
None

.OUTPUTS
System.Management.Automation.PSCustomObject

Returns an object with the following properties:

- ModRM        [byte]
- Displacement [byte[]]

Returns $null if validation fails.

.NOTES
This function performs lightweight binary structure validation only.
It does not perform full binary analysis.
#>
function Get-BeforeInstruction {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [ValidateRange(0, [Int64]::MaxValue)]
        [Int64]$ReferenceIndex
    )

    process {
        try {
            [Int64]$instructionStart = $ReferenceIndex - 6

            if ($instructionStart -lt 0) {
                Write-Verbose -Message "Preceding instruction region exceeds lower bounds."
                return $null
            }

            if (($instructionStart + 5) -ge $Bytes.Length) {
                Write-Verbose -Message "Preceding instruction region exceeds upper bounds."
                return $null
            }

            # Validate opcode (0x8B)
            if ($Bytes[$instructionStart] -ne 0x8B) {
                Write-Verbose -Message "Preceding opcode validation failed."
                return $null
            }

            [byte]$modRM = $Bytes[$instructionStart + 1]

            [byte[]]$displacement = @(
                $Bytes[$instructionStart + 2]
                $Bytes[$instructionStart + 3]
                $Bytes[$instructionStart + 4]
                $Bytes[$instructionStart + 5]
            )

            # Expected displacement anchor
            [byte[]]$expectedDisplacement = 0x38, 0x06, 0x00, 0x00

            for ([int]$i = 0; $i -lt $expectedDisplacement.Length; $i++) {
                if ($displacement[$i] -ne $expectedDisplacement[$i]) {
                    Write-Verbose -Message "Displacement validation failed."
                    return $null
                }
            }

            Write-Verbose -Message "Preceding instruction validated successfully."

            return [PSCustomObject]@{
                PSTypeName   = 'RDPControl.BinaryInstructionContext'
                ModRM        = $modRM
                Displacement = $displacement
            }
        } catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                "BinaryInstructionValidationFailed",
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $ReferenceIndex
            )

            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
}
