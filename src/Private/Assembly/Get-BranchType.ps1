<#
.SYNOPSIS
Identifies the conditional branch type immediately following a reference sequence.

.DESCRIPTION
Inspects the bytes immediately after a reference sequence and identifies
known conditional branch signatures.

Currently supported branch types:

    Equal
        0F 84  -> conditional branch if equal / zero

    NotEqual
        75     -> conditional branch if not equal / non-zero

Returns 'Unknown' when no supported branch signature is identified.

.PARAMETER Bytes
Byte array containing the binary content to inspect.

.PARAMETER ReferenceIndex
Byte index where the reference sequence begins.

.PARAMETER ReferenceLength
Length in bytes of the reference sequence.

.EXAMPLE
PS C:\> Get-BranchType -Bytes $bytes -ReferenceIndex 0x1E815 -ReferenceLength 6

.INPUTS
None

.OUTPUTS
System.String

Returns one of the following values:

- Equal
- NotEqual
- Unknown

.NOTES
This function performs lightweight binary signature inspection only.
It does not perform full instruction decoding or disassembly.
#>
function Get-BranchType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$ReferenceIndex,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ReferenceLength
    )

    process {
        try {
            [int]$branchIndex = $ReferenceIndex + $ReferenceLength

            if (($branchIndex + 1) -ge $Bytes.Length) {
                Write-Verbose -Message ("Branch inspection exceeds byte array bounds.")
                return 'Unknown'
            }

            # NotEqual branch signature (75)
            if ($Bytes[$branchIndex] -eq 0x75) {
                Write-Verbose -Message ("Detected branch type: NotEqual")
                return 'NotEqual'
            }

            # Equal branch signature (0F 84)
            if (Test-ByteSequence -Source $Bytes -Offset $branchIndex -Expected @(0x0F, 0x84)) {
                Write-Verbose -Message ("Detected branch type: Equal")
                return 'Equal'
            }

            Write-Verbose -Message ("No supported branch signature detected.")
            return 'Unknown'
        } catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                "BranchTypeDetectionFailed",
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $ReferenceIndex
            )

            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
}
