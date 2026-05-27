Describe 'Get-BeforeInstruction' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BeforeInstruction.ps1"

        # Valid BEFORE layout (6 bytes immediately preceding the core pattern):
        #
        #   [0x8B] [ModRM] [38 06 00 00]
        #
        #   0x8B = mov r32, [base+disp32]
        #   ModRM encodes target register
        #   disp32 = 0x00000638
        #
        # Core reference pattern:
        #
        #   39 81 3C 06 00 00
        #
        function New-TestByteArray {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions',
                '',
                Justification = 'Internal test helper.'
            )]
            param (
                [byte]$Opcode = 0x8B,
                [byte]$ModRM = 0x81,
                [byte[]]$Displacement = @(0x38, 0x06, 0x00, 0x00),
                [int]$PaddingBefore = 0
            )

            [System.Collections.Generic.List[byte]]$buffer = [System.Collections.Generic.List[byte]]::new()

            for ($i = 0; $i -lt $PaddingBefore; $i++) {
                $buffer.Add(0x90)
            }

            # BEFORE instruction
            $buffer.Add($Opcode)
            $buffer.Add($ModRM)

            foreach ($byte in $Displacement) {
                $buffer.Add($byte)
            }

            # CORE pattern
            $buffer.Add(0x39)
            $buffer.Add(0x81)
            $buffer.Add(0x3C)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            return [byte[]]$buffer.ToArray()
        }
    }

    Context 'Valid preceding instruction' {

        It 'Returns ModRM and displacement for mov eax, [rcx+0x638]' {
            [byte[]]$bytes = New-TestByteArray

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $result | Should -Not -BeNullOrEmpty

            $result.ModRM | Should -Be 0x81

            $result.Displacement | Should -HaveCount 4

            $result.Displacement[0] | Should -Be 0x38
            $result.Displacement[1] | Should -Be 0x06
            $result.Displacement[2] | Should -Be 0x00
            $result.Displacement[3] | Should -Be 0x00
        }

        It 'Extracts ModRM 0x91 for mov edx, [rcx+0x638]' {
            [byte[]]$bytes = New-TestByteArray -ModRM 0x91

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $result | Should -Not -BeNullOrEmpty
            $result.ModRM | Should -Be 0x91
        }

        It 'Works when instruction is embedded deeper in the byte array' {
            [byte[]]$bytes = New-TestByteArray -PaddingBefore 4

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 10

            $result | Should -Not -BeNullOrEmpty
            $result.ModRM | Should -Be 0x81
        }

        It 'Uses the 6 bytes immediately preceding ReferenceIndex only' {
            [byte[]]$bytes = @(
                # Valid sequence FAR AWAY
                0x8B, 0x81, 0x38, 0x06, 0x00, 0x00,

                # Padding
                0x90, 0x90, 0x90,

                # Core
                0x39, 0x81, 0x3C, 0x06, 0x00, 0x00
            )

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 9

            $result | Should -Be $null
        }
    }

    Context 'Invalid preceding instruction' {

        It 'Returns $null when opcode is not 0x8B' {
            [byte[]]$bytes = New-TestByteArray -Opcode 0x89

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $result | Should -Be $null
        }

        It 'Rejects valid displacement when opcode encoding is unsupported' {
            [byte[]]$bytes = New-TestByteArray -Opcode 0xFF

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $result | Should -Be $null
        }

        It 'Returns $null when displacement anchor does not match' {
            [byte[]]$bytes = New-TestByteArray -Displacement @(0xFF, 0xFF, 0x00, 0x00)

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $result | Should -Be $null
        }

        It 'Returns $null when a single displacement byte differs' {
            [byte[]]$bytes = New-TestByteArray -Displacement @(0x38, 0x07, 0x00, 0x00)

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $result | Should -Be $null
        }

        It 'Returns $null when all preceding bytes are NOPs' {
            [byte[]]$bytes = @(
                0x90, 0x90, 0x90,
                0x90, 0x90, 0x90,
                0x39, 0x81, 0x3C,
                0x06, 0x00, 0x00
            )

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $result | Should -Be $null
        }
    }

    Context 'Boundary conditions' {

        It 'Returns $null when ReferenceIndex is 0' {
            [byte[]]$bytes = @(
                0x39, 0x81, 0x3C,
                0x06, 0x00, 0x00
            )

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 0

            $result | Should -Be $null
        }

        It 'Returns $null when ReferenceIndex is less than 6' {
            [byte[]]$bytes = @(
                0x8B, 0x81, 0x38,
                0x39, 0x81, 0x3C,
                0x06, 0x00, 0x00
            )

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 3

            $result | Should -Be $null
        }

        It 'Returns $null when only 5 bytes precede the reference index' {
            [byte[]]$bytes = @(
                0x8B, 0x81, 0x38,
                0x06, 0x00,
                0x39, 0x81, 0x3C,
                0x06, 0x00, 0x00
            )

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 5

            $result | Should -Be $null
        }
    }

    Context 'Output structure' {

        It 'Returns an object with ModRM and Displacement properties' {
            [byte[]]$bytes = New-TestByteArray

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $result.PSObject.Properties.Name | Should -Contain 'ModRM'
            $result.PSObject.Properties.Name | Should -Contain 'Displacement'
        }

        It 'Returns Displacement as a 4-byte array' {
            [byte[]]$bytes = New-TestByteArray

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $result.Displacement | Should -HaveCount 4
        }

        It 'Does not modify the input byte array' {
            [byte[]]$bytes = New-TestByteArray

            [byte[]]$original = $bytes.Clone()

            $null = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $bytes | Should -Be $original
        }

        It 'Has PSTypeName RDPControl.BinaryInstructionContext' {
            [byte[]]$bytes = New-TestByteArray

            $result = Get-BeforeInstruction -Bytes $bytes -ReferenceIndex 6

            $result.PSTypeNames | Should -Contain 'RDPControl.BinaryInstructionContext'
        }
    }
}
