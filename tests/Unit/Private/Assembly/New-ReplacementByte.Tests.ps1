Describe 'New-ReplacementByte' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/New-ReplacementByte.ps1"
    }

    # Replacement layout for jz (12 bytes):
    #   [B8+reg] [00 01 00 00] [89] [ModRM] [disp32] [90]
    #
    # Replacement layout for jne (13 bytes):
    #   [B8+reg] [00 01 00 00] [89] [ModRM] [disp32] [90] [EB]

    Context 'jz context (Windows 10 / Windows 11 up to 23H2)' {

        It 'Generates a 12-byte replacement sequence for eax context' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            [byte[]]$result = New-ReplacementByte -ModRM 0x81 -Displacement $displacement -JumpType 'jz'

            $result.GetType() | Should -Be ([byte[]])
            $result | Should -HaveCount 12

            $expected = [byte[]]@(
                0xB8,             # mov eax, imm32
                0x00, 0x01, 0x00, 0x00,
                0x89,             # mov [base+disp32], r32
                0x81,             # preserved ModRM
                0x38, 0x06, 0x00, 0x00,
                0x90              # NOP
            )

            $result | Should -Be $expected
        }

        It 'Preserves displacement bytes exactly' {
            [byte[]]$displacement = 0xAA, 0xBB, 0xCC, 0xDD

            $result = New-ReplacementByte -ModRM 0x81 -Displacement $displacement -JumpType 'jz'

            $result[7..10] | Should -Be $displacement
        }
    }

    Context 'jne context (Windows 11 24H2 and later)' {

        It 'Generates a 13-byte replacement sequence with trailing EB' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            [byte[]]$result = New-ReplacementByte -ModRM 0x81 -Displacement $displacement -JumpType 'jne'

            $result.GetType() | Should -Be ([byte[]])
            $result | Should -HaveCount 13

            $expected = [byte[]]@(
                0xB8, 0x00, 0x01, 0x00, 0x00,
                0x89, 0x81, 0x38, 0x06, 0x00,
                0x00, 0x90, 0xEB
            )

            $result | Should -Be $expected
        }
    }

    Context 'Register field extraction from ModRM' {

        It 'Computes opcode B8+reg for all supported register encodings' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            $testCases = @(
                @{ ModRM = 0x81; ExpectedOpcode = 0xB8 } # eax
                @{ ModRM = 0x89; ExpectedOpcode = 0xB9 } # ecx
                @{ ModRM = 0x91; ExpectedOpcode = 0xBA } # edx
                @{ ModRM = 0x99; ExpectedOpcode = 0xBB } # ebx
                @{ ModRM = 0xA1; ExpectedOpcode = 0xBC } # esp
                @{ ModRM = 0xA9; ExpectedOpcode = 0xBD } # ebp
                @{ ModRM = 0xB1; ExpectedOpcode = 0xBE } # esi
                @{ ModRM = 0xB9; ExpectedOpcode = 0xBF } # edi
            )

            foreach ($case in $testCases) {

                $result = New-ReplacementByte -ModRM $case.ModRM -Displacement $displacement -JumpType 'jz'

                $result[0] | Should -Be $case.ExpectedOpcode -Because (
                    'ModRM 0x{0:X2} encodes register {1}' -f
                    $case.ModRM,
                    (($case.ModRM -shr 3) -band 0x07)
                )
            }
        }
    }

    Context 'Replacement constant encoding' {

        It 'Embeds 0x00000100 as little-endian imm32 for jz' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            $result = New-ReplacementByte -ModRM 0x81 -Displacement $displacement -JumpType 'jz'

            $result[1..4] | Should -Be ([byte[]]@(0x00, 0x01, 0x00, 0x00))
        }

        It 'Embeds the same imm32 value for jne' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            $result = New-ReplacementByte -ModRM 0x81 -Displacement $displacement -JumpType 'jne'

            $result[1..4] | Should -Be ([byte[]]@(0x00, 0x01, 0x00, 0x00))
        }
    }

    Context 'ModRM preservation' {

        It 'Preserves the original ModRM byte at offset 6' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            $result = New-ReplacementByte -ModRM 0x91 -Displacement $displacement -JumpType 'jz'

            $result[6] | Should -Be 0x91
        }
    }

    Context 'Parameter validation' {

        It 'Rejects displacement arrays shorter than 4 bytes' {
            {
                New-ReplacementByte -ModRM 0x81 -Displacement @(0x38, 0x06, 0x00) -JumpType 'jz'
            } | Should -Throw
        }

        It 'Rejects displacement arrays longer than 4 bytes' {
            {
                New-ReplacementByte -ModRM 0x81 -Displacement @(0x38, 0x06, 0x00, 0x00, 0xFF) -JumpType 'jz'
            } | Should -Throw
        }

        It 'Rejects unsupported JumpType values' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            { New-ReplacementByte -ModRM 0x81 -Displacement $displacement -JumpType 'unknown' } |
                Should -Throw
        }

        It 'Rejects ModRM values with mod=00b' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            { New-ReplacementByte -ModRM 0x01 -Displacement $displacement -JumpType 'jz' } |
                Should -Throw -ExpectedMessage '*Unsupported ModR/M encoding*'
        }

        It 'Rejects ModRM values with mod=01b' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            { New-ReplacementByte -ModRM 0x41 -Displacement $displacement -JumpType 'jz' } |
                Should -Throw -ExpectedMessage '*Unsupported ModR/M encoding*'
        }

        It 'Rejects ModRM values with mod=11b' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            { New-ReplacementByte -ModRM 0xC1 -Displacement $displacement -JumpType 'jz' } |
                Should -Throw -ExpectedMessage '*Unsupported ModR/M encoding*'
        }
    }

    Context 'Output type' {

        It 'Returns a byte array' {
            [byte[]]$displacement = 0x38, 0x06, 0x00, 0x00

            [byte[]]$result = New-ReplacementByte -ModRM 0x81 -Displacement $displacement -JumpType 'jz'

            $result.GetType() | Should -Be ([byte[]])
        }
    }
}
