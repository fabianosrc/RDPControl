Describe 'Test-ByteSequence' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Test-ByteSequence.ps1"
    }

    Context 'Exact match at offset' {

        It 'Returns $true when Expected matches Source at Offset' {
            [byte[]]$source   = 0x00, 0x39, 0x81, 0x3C, 0x00
            [byte[]]$expected = 0x39, 0x81, 0x3C

            Test-ByteSequence -Source $source -Offset 1 -Expected $expected |
                Should -BeTrue
        }

        It 'Returns $true when Expected matches at offset 0' {
            [byte[]]$source   = 0xAA, 0xBB, 0xCC
            [byte[]]$expected = 0xAA, 0xBB

            Test-ByteSequence -Source $source -Offset 0 -Expected $expected |
                Should -BeTrue
        }

        It 'Returns $true when Expected matches at the last valid position' {
            [byte[]]$source   = 0x00, 0x00, 0xFF, 0xFE
            [byte[]]$expected = 0xFF, 0xFE

            Test-ByteSequence -Source $source -Offset 2 -Expected $expected |
                Should -BeTrue
        }

        It 'Returns $true for a single-byte Expected that matches' {

            [byte[]]$source   = 0x10, 0x20, 0x30
            [byte[]]$expected = 0x20

            Test-ByteSequence -Source $source -Offset 1 -Expected $expected |
                Should -BeTrue
        }

        It 'Returns $true when Expected equals the entire Source at offset 0' {
            [byte[]]$source   = 0x0F, 0x84
            [byte[]]$expected = 0x0F, 0x84

            Test-ByteSequence -Source $source -Offset 0 -Expected $expected |
                Should -BeTrue
        }
    }

    Context 'Mismatch detection' {

        It 'Returns $false when first byte differs' {
            [byte[]]$source   = 0x00, 0x39, 0x81
            [byte[]]$expected = 0xFF, 0x81

            Test-ByteSequence -Source $source -Offset 1 -Expected $expected |
                Should -BeFalse
        }

        It 'Returns $false when a middle byte differs' {
            [byte[]]$source   = 0x39, 0x81, 0x3C, 0x06
            [byte[]]$expected = 0x39, 0xFF, 0x3C

            Test-ByteSequence -Source $source -Offset 0 -Expected $expected |
                Should -BeFalse
        }

        It 'Returns $false when last byte differs' {
            [byte[]]$source   = 0x39, 0x81, 0x3C
            [byte[]]$expected = 0x39, 0x81, 0xFF

            Test-ByteSequence -Source $source -Offset 0 -Expected $expected |
                Should -BeFalse
        }

        It 'Returns $false when Expected is larger than Source' {
            [byte[]]$source   = 0xAA, 0xBB
            [byte[]]$expected = 0xAA, 0xBB, 0xCC

            Test-ByteSequence -Source $source -Offset 0 -Expected $expected |
                Should -BeFalse
        }
    }

    Context 'Boundary conditions' {

        It 'Returns $false when Offset is negative' {
            [byte[]]$source   = 0xAA, 0xBB
            [byte[]]$expected = 0xAA

            Test-ByteSequence -Source $source -Offset -1 -Expected $expected |
                Should -BeFalse
        }

        It 'Returns $false when Expected extends beyond Source bounds' {
            [byte[]]$source   = 0xAA, 0xBB, 0xCC
            [byte[]]$expected = 0xBB, 0xCC, 0xDD

            Test-ByteSequence -Source $source -Offset 1 -Expected $expected |
                Should -BeFalse
        }

        It 'Returns $false when Offset equals Source length' {
            [byte[]]$source   = 0xAA, 0xBB
            [byte[]]$expected = 0xAA

            Test-ByteSequence -Source $source -Offset 2 -Expected $expected |
                Should -BeFalse
        }

        It 'Returns $false when Offset greatly exceeds Source length' {
            [byte[]]$source   = 0xAA
            [byte[]]$expected = 0xAA

            Test-ByteSequence -Source $source -Offset 100 -Expected $expected |
                Should -BeFalse
        }
    }

    Context 'Real-world patterns' {

        It 'Detects the core pattern embedded in a larger array' {
            [byte[]]$source = @(
                0x8B, 0x81, 0x38, 0x06, 0x00, 0x00,
                0x39, 0x81, 0x3C, 0x06, 0x00, 0x00,
                0x0F, 0x84, 0x00, 0x00, 0x00, 0x00
            )

            [byte[]]$corePattern = 0x39, 0x81, 0x3C, 0x06, 0x00, 0x00

            Test-ByteSequence -Source $source -Offset 6 -Expected $corePattern |
                Should -BeTrue
        }

        It 'Returns $false for the core pattern at the wrong offset' {
            [byte[]]$source = @(
                0x8B, 0x81, 0x38, 0x06, 0x00, 0x00,
                0x39, 0x81, 0x3C, 0x06, 0x00, 0x00
            )

            [byte[]]$corePattern = 0x39, 0x81, 0x3C, 0x06, 0x00, 0x00

            Test-ByteSequence -Source $source -Offset 0 -Expected $corePattern |
                Should -BeFalse
        }

        It 'Detects jz opcode pair (0F 84)' {
            [byte[]]$source   = 0x0F, 0x84, 0xAA, 0xBB, 0xCC, 0xDD
            [byte[]]$expected = 0x0F, 0x84

            Test-ByteSequence -Source $source -Offset 0 -Expected $expected |
                Should -BeTrue
        }

        It 'Detects jne opcode (75 xx)' {
            [byte[]]$source   = 0x75, 0x0A
            [byte[]]$expected = 0x75

            Test-ByteSequence -Source $source -Offset 0 -Expected $expected |
                Should -BeTrue
        }
    }

    Context 'Output type' {

        It 'Returns System.Boolean' {
            [byte[]]$source   = 0xAA, 0xBB
            [byte[]]$expected = 0xAA

            $result = Test-ByteSequence -Source $source -Offset 0 -Expected $expected

            $result | Should -BeOfType ([bool])
        }
    }
}
