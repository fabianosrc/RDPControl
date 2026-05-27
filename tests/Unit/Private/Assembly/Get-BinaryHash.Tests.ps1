Describe 'Get-BinaryHash' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BinaryHash.ps1"

        function Get-ExpectedSha256 {
            [CmdletBinding()]
            [OutputType([string])]
            param (
                [Parameter(Mandatory)]
                [byte[]]$Bytes
            )

            $sha256 = [System.Security.Cryptography.SHA256]::Create()

            try {
                [byte[]]$hash = $sha256.ComputeHash($Bytes)

                return [string]::Join('', ($hash | ForEach-Object { $_.ToString('x2') }))
            } finally {
                $sha256.Dispose()
            }
        }
    }

    Context 'Known hash values' {

        It 'Returns the correct SHA256 for the ASCII string "Hello"' {
            [byte[]]$bytes = 0x48, 0x65, 0x6C, 0x6C, 0x6F

            $expected = Get-ExpectedSha256 -Bytes $bytes

            $result = Get-BinaryHash -Bytes $bytes

            $result | Should -Be $expected
        }

        It 'Returns the correct SHA256 for a single null byte' {
            [byte[]]$bytes = 0x00

            $expected = Get-ExpectedSha256 -Bytes $bytes

            $result = Get-BinaryHash -Bytes $bytes

            $result | Should -Be $expected
        }
    }

    Context 'Output format' {

        It 'Returns a 64-character hexadecimal string' {
            [byte[]]$bytes = 0x01, 0x02, 0x03

            $result = Get-BinaryHash -Bytes $bytes

            $result.Length | Should -Be 64
        }

        It 'Returns uppercase hexadecimal characters only' {
            [byte[]]$bytes = 0xFF, 0xAA, 0x00, 0x55

            $result = Get-BinaryHash -Bytes $bytes

            $result | Should -Match '^[0-9A-F]{64}$'
        }

        It 'Returns a value of type System.String' {
            [byte[]]$bytes = 0x01

            $result = Get-BinaryHash -Bytes $bytes

            $result | Should -BeOfType [string]
        }

        It 'Does not return whitespace or separators' {
            [byte[]]$bytes = 0x10, 0x20, 0x30

            $result = Get-BinaryHash -Bytes $bytes

            $result | Should -Not -Match '\s|-|:'
        }
    }

    Context 'Determinism' {

        It 'Returns identical hashes for identical byte arrays' {
            [byte[]]$bytes1 = 0x01, 0x02, 0x03, 0x04, 0x05
            [byte[]]$bytes2 = 0x01, 0x02, 0x03, 0x04, 0x05

            $hash1 = Get-BinaryHash -Bytes $bytes1
            $hash2 = Get-BinaryHash -Bytes $bytes2

            $hash1 | Should -Be $hash2
        }

        It 'Returns different hashes when one byte differs' {
            [byte[]]$bytes1 = 0x01, 0x02, 0x03
            [byte[]]$bytes2 = 0x01, 0x02, 0x04

            $hash1 = Get-BinaryHash -Bytes $bytes1
            $hash2 = Get-BinaryHash -Bytes $bytes2

            $hash1 | Should -Not -Be $hash2
        }

        It 'Returns different hashes when byte order changes' {
            [byte[]]$bytes1 = 0xAA, 0xBB
            [byte[]]$bytes2 = 0xBB, 0xAA

            $hash1 = Get-BinaryHash -Bytes $bytes1
            $hash2 = Get-BinaryHash -Bytes $bytes2

            $hash1 | Should -Not -Be $hash2
        }

        It 'Returns the same hash across repeated executions' {
            [byte[]]$bytes = 0xDE, 0xAD, 0xBE, 0xEF

            $results = for ($i = 0; $i -lt 5; $i++) {
                Get-BinaryHash -Bytes $bytes
            }

            $results | Select-Object -Unique | Should -HaveCount 1
        }
    }

    Context 'Boundary conditions' {

        It 'Handles a single-byte array' {
            [byte[]]$bytes = 0x7F

            { Get-BinaryHash -Bytes $bytes } | Should -Not -Throw
        }

        It 'Handles a very small two-byte array' {
            [byte[]]$bytes = 0x00, 0x01

            { Get-BinaryHash -Bytes $bytes } | Should -Not -Throw
        }

        It 'Handles arrays containing only zero bytes' {
            [byte[]]$bytes = [byte[]]::new(32)

            $result = Get-BinaryHash -Bytes $bytes

            $result | Should -Match '^[0-9A-F]{64}$'
        }

        It 'Handles arrays containing only 0xFF bytes' {
            [byte[]]$bytes = [byte[]]::new(32)

            for ($i = 0; $i -lt $bytes.Length; $i++) {
                $bytes[$i] = 0xFF
            }

            $result = Get-BinaryHash -Bytes $bytes

            $result | Should -Match '^[0-9A-F]{64}$'
        }
    }

    Context 'Large input' {

        It 'Handles a 1 MB byte array without error' {
            [byte[]]$bytes = [byte[]]::new(1MB)

            { Get-BinaryHash -Bytes $bytes } | Should -Not -Throw
        }

        It 'Returns a valid hash for a 1 MB byte array' {
            [byte[]]$bytes = [byte[]]::new(1MB)

            $result = Get-BinaryHash -Bytes $bytes

            $result.Length | Should -Be 64
            $result | Should -Match '^[0-9A-F]{64}$'
        }

        It 'Produces deterministic hashes for large inputs' {
            [byte[]]$bytes = [byte[]]::new(1MB)

            for ($i = 0; $i -lt $bytes.Length; $i++) {
                $bytes[$i] = [byte]($i % 256)
            }

            $hash1 = Get-BinaryHash -Bytes $bytes
            $hash2 = Get-BinaryHash -Bytes $bytes

            $hash1 | Should -Be $hash2
        }
    }

    Context 'Input immutability' {

        It 'Does not modify the original byte array' {
            [byte[]]$bytes = 0x01, 0x02, 0x03, 0x04

            [byte[]]$original = $bytes.Clone()

            $null = Get-BinaryHash -Bytes $bytes

            $bytes | Should -Be $original
        }
    }
}
