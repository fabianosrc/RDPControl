Describe 'Get-BranchType' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Test-ByteSequence.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BranchType.ps1"

        function New-BranchTestBuffer {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions',
                '',
                Justification = 'Internal test helper.'
            )]
            param (
                [byte[]]$BranchBytes,
                [int]$PaddingBefore = 0
            )

            [System.Collections.Generic.List[byte]]$buffer = [System.Collections.Generic.List[byte]]::new()

            for ($i = 0; $i -lt $PaddingBefore; $i++) {
                $buffer.Add(0xCC)
            }

            # Core pattern
            $buffer.Add(0x39)
            $buffer.Add(0x81)
            $buffer.Add(0x3C)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            foreach ($byteValue in $BranchBytes) {
                $buffer.Add($byteValue)
            }

            return [byte[]]$buffer.ToArray()
        }
    }

    Context 'jz detection (Windows 10 / Win11 <= 23H2)' {

        It 'Returns jz for canonical 0F 84 rel32 sequence' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(
                0x0F, 0x84,
                0x00, 0x00, 0x00, 0x00
            )

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -Be 'jz'
        }

        It 'Ignores rel32 displacement contents for jz detection' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(
                0x0F, 0x84,
                0xFF, 0xAA, 0x55, 0x10
            )

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -Be 'jz'
        }
    }

    Context 'jne detection (Windows 11 24H2+)' {

        It 'Returns jne for canonical 75 rel8 sequence' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(0x75, 0x0A)

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -Be 'jne'
        }

        It 'Ignores rel8 displacement contents for jne detection' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(0x75, 0xFF)

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -Be 'jne'
        }
    }

    Context 'Unknown branch detection' {

        It 'Returns unknown for unsupported opcodes' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(0x90, 0x90)

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -Be 'unknown'
        }

        It 'Rejects jnz rel32 (0F 85)' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(
                0x0F, 0x85,
                0x00, 0x00, 0x00, 0x00
            )

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -Be 'unknown'
        }

        It 'Rejects short-form jz (74 rel8)' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(0x74, 0x0A)

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -Be 'unknown'
        }
    }

    Context 'Boundary conditions' {

        It 'Returns unknown when branch sequence is truncated after 0F' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(0x0F)

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -Be 'unknown'
        }

        It 'Returns unknown when no bytes exist after the core pattern' {
            [byte[]]$bytes = @(0x39, 0x81, 0x3C, 0x06, 0x00, 0x00)

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -Be 'unknown'
        }

        It 'Returns unknown when ReferenceIndex exceeds array bounds' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(0x75, 0x01)

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 999 -ReferenceLength 6

            $result | Should -Be 'unknown'
        }
    }

    Context 'ReferenceIndex handling' {

        It 'Correctly computes branch location with non-zero ReferenceIndex (jne)' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(0x75, 0x0A) -PaddingBefore 5

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 5 -ReferenceLength 6

            $result | Should -Be 'jne'
        }

        It 'Correctly computes branch location with non-zero ReferenceIndex (jz)' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(
                0x0F, 0x84, 0x10, 0x00, 0x00, 0x00
            ) -PaddingBefore 8

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 8 -ReferenceLength 6

            $result | Should -Be 'jz'
        }
    }

    Context 'Detection priority' {

        It 'Prioritizes jne detection when first opcode byte is 0x75' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(0x75, 0x84)

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -Be 'jne'
        }
    }

    Context 'Return contract' {

        It 'Returns only supported branch identifiers' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(0x90, 0x90)

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -BeIn @('jz', 'jne', 'unknown')
        }

        It 'Returns a System.String instance' {
            [byte[]]$bytes = New-BranchTestBuffer -BranchBytes @(0x75, 0x01)

            $result = Get-BranchType -Bytes $bytes -ReferenceIndex 0 -ReferenceLength 6

            $result | Should -BeOfType [string]
        }
    }
}
