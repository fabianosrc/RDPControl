Describe 'Get-ByteRange' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-ByteRange.ps1"

        function Assert-ByteSequence {
            param (
                [byte[]]$Actual,
                [byte[]]$Expected
            )

            $Actual | Should -HaveCount $Expected.Length

            for ($i = 0; $i -lt $Expected.Length; $i++) {
                $Actual[$i] | Should -Be $Expected[$i]
            }
        }
    }

    Context 'Normal extraction' {

        It 'Extracts a slice from the middle of the array' {
            [byte[]]$bytes = 0x00, 0x11, 0x22, 0x33, 0x44, 0x55

            $result = Get-ByteRange -Bytes $bytes -Start 2 -Length 3

            Assert-ByteSequence -Actual $result -Expected ([byte[]](0x22, 0x33, 0x44))
        }

        It 'Extracts bytes from offset 0' {
            [byte[]]$bytes = 0xAA, 0xBB, 0xCC, 0xDD

            $result = Get-ByteRange -Bytes $bytes -Start 0 -Length 2

            Assert-ByteSequence -Actual $result -Expected ([byte[]](0xAA, 0xBB))
        }

        It 'Returns the entire array when requested range matches array size' {
            [byte[]]$bytes = 0x01, 0x02, 0x03

            $result = Get-ByteRange -Bytes $bytes -Start 0 -Length 3

            Assert-ByteSequence -Actual $result -Expected $bytes
        }

        It 'Returns a single-byte slice' {
            [byte[]]$bytes = 0x10, 0x20, 0x30

            $result = Get-ByteRange -Bytes $bytes -Start 1 -Length 1

            Assert-ByteSequence -Actual $result -Expected ([byte[]](0x20))
        }

        It 'Extracts the last bytes of the array' {
            [byte[]]$bytes = 0x01, 0x02, 0x03, 0x04, 0x05

            $result = Get-ByteRange -Bytes $bytes -Start 3 -Length 2

            Assert-ByteSequence -Actual $result -Expected ([byte[]](0x04, 0x05))
        }
    }

    Context 'Clamping behavior' {

        It 'Clamps negative Start values to 0' {
            [byte[]]$bytes = 0xAA, 0xBB, 0xCC

            $result = Get-ByteRange -Bytes $bytes -Start -100 -Length 2

            Assert-ByteSequence -Actual $result -Expected ([byte[]](0xAA, 0xBB))
        }

        It 'Clamps extraction length to available bytes' {
            [byte[]]$bytes = 0x10, 0x20, 0x30, 0x40

            $result = Get-ByteRange -Bytes $bytes -Start 2 -Length 999

            Assert-ByteSequence -Actual $result -Expected ([byte[]](0x30, 0x40))
        }

        It 'Returns only the final byte when Start points to the last index' {
            [byte[]]$bytes = 0x01, 0x02, 0x03, 0x04, 0x05

            $result = Get-ByteRange -Bytes $bytes -Start 4 -Length 100

            Assert-ByteSequence -Actual $result -Expected ([byte[]](0x05))
        }
    }

    Context 'Boundary conditions' {

        It 'Returns an empty array when Start exceeds array bounds' {
            [byte[]]$bytes = 0x01, 0x02, 0x03

            $result = Get-ByteRange -Bytes $bytes -Start 999 -Length 5

            $result | Should -BeNullOrEmpty
        }

        It 'Returns an empty array when Length is 0' {
            [byte[]]$bytes = 0xAA, 0xBB

            $result = Get-ByteRange -Bytes $bytes -Start 0 -Length 0

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Immutability' {

        It 'Does not modify the original array' {
            [byte[]]$bytes = 0x10, 0x20, 0x30, 0x40
            [byte[]]$original = $bytes.Clone()

            $null = Get-ByteRange -Bytes $bytes -Start 1 -Length 2

            Assert-ByteSequence -Actual $bytes -Expected $original
        }

        It 'Returns a new array instance' {
            [byte[]]$bytes = 0x01, 0x02, 0x03

            $result = Get-ByteRange -Bytes $bytes -Start 0 -Length 3

            [object]::ReferenceEquals($bytes, $result) | Should -BeFalse
        }
    }

    Context 'Real-world usage: binary signature scanning' {

        It 'Extracts a 6-byte BEFORE context window' {
            [byte[]]$bytes = @(
                0x8B, 0x81, 0x38, 0x06, 0x00, 0x00,
                0x39, 0x81, 0x3C, 0x06, 0x00, 0x00,
                0x0F, 0x84, 0x00, 0x00, 0x00, 0x00
            )

            $result = Get-ByteRange -Bytes $bytes -Start 0 -Length 6

            Assert-ByteSequence -Actual $result -Expected (
                [byte[]](0x8B, 0x81, 0x38, 0x06, 0x00, 0x00)
            )
        }

        It 'Extracts a 6-byte AFTER context window' {
            [byte[]]$bytes = @(
                0x8B, 0x81, 0x38, 0x06, 0x00, 0x00,
                0x39, 0x81, 0x3C, 0x06, 0x00, 0x00,
                0x0F, 0x84, 0xAA, 0xBB, 0xCC, 0xDD
            )

            $result = Get-ByteRange -Bytes $bytes -Start 12 -Length 6

            Assert-ByteSequence -Actual $result -Expected ([byte[]](
                0x0F, 0x84, 0xAA, 0xBB, 0xCC, 0xDD
            ))
        }
    }

    Context 'Return contract' {

        It 'Returns a byte array' {
            [byte[]]$bytes = 0x01, 0x02, 0x03

            [byte[]]$result = Get-ByteRange -Bytes $bytes -Start 0 -Length 2

            $result.GetType() | Should -Be ([byte[]])
        }

        It 'Returns deterministic results for identical inputs' {
            [byte[]]$bytes = 0xAA, 0xBB, 0xCC, 0xDD

            [byte[]]$result1 = Get-ByteRange -Bytes $bytes -Start 1 -Length 2

            [byte[]]$result2 = Get-ByteRange -Bytes $bytes -Start 1 -Length 2

            Assert-ByteSequence -Actual $result1 -Expected $result2
        }
    }
}
