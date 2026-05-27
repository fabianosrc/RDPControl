Describe 'Get-PEArchitecture' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-PEArchitecture.ps1"

        function New-MinimalPE {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions',
                '',
                Justification = 'Internal Pester helper function.'
            )]
            param (
                [Parameter(Mandatory)]
                [ValidateSet(0x10B, 0x20B, 0x107)]
                [UInt16]$Magic
            )

            [byte[]]$pe = [byte[]]::new(256)

            # DOS header (MZ)
            $pe[0] = 0x4D
            $pe[1] = 0x5A

            # e_lfanew -> 0x80
            [byte[]]$lfanew = [System.BitConverter]::GetBytes([UInt32]0x80)
            [Array]::Copy($lfanew, 0, $pe, 0x3C, 4)

            # PE\0\0 signature
            $pe[0x80] = 0x50
            $pe[0x81] = 0x45
            $pe[0x82] = 0x00
            $pe[0x83] = 0x00

            # IMAGE_OPTIONAL_HEADER.Magic
            [byte[]]$magicBytes = [System.BitConverter]::GetBytes($Magic)
            [Array]::Copy($magicBytes, 0, $pe, 0x98, 2)

            return $pe
        }
    }

    Context 'Bytes parameter set' {

        It 'Returns x64 for PE32+ images' {
            [byte[]]$pe = New-MinimalPE -Magic 0x20B

            $result = Get-PEArchitecture -Bytes $pe

            $result | Should -BeExactly 'x64'
        }

        It 'Returns x86 for PE32 images' {
            [byte[]]$pe = New-MinimalPE -Magic 0x10B

            $result = Get-PEArchitecture -Bytes $pe

            $result | Should -BeExactly 'x86'
        }

        It 'Returns ROM for ROM images' {
            [byte[]]$pe = New-MinimalPE -Magic 0x107

            $result = Get-PEArchitecture -Bytes $pe

            $result | Should -BeExactly 'ROM'
        }

        It 'Throws for unknown optional header magic values' {
            [byte[]]$pe = [byte[]]::new(256)

            $pe[0] = 0x4D
            $pe[1] = 0x5A

            [byte[]]$lfanew = [System.BitConverter]::GetBytes([UInt32]0x80)
            [Array]::Copy($lfanew, 0, $pe, 0x3C, 4)

            $pe[0x80] = 0x50
            $pe[0x81] = 0x45
            $pe[0x82] = 0x00
            $pe[0x83] = 0x00

            [byte[]]$magicBytes = [System.BitConverter]::GetBytes([UInt16]0x999)
            [Array]::Copy($magicBytes, 0, $pe, 0x98, 2)

            { Get-PEArchitecture -Bytes $pe } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException]) `
                -ExpectedMessage '*Unknown PE optional header magic value*'
        }
    }

    Context 'Path parameter set' {

        BeforeAll {
            $Script:TestDirectory = Join-Path -Path $TestDrive -ChildPath 'PEFiles'

            New-Item -Path $Script:TestDirectory -ItemType Directory -Force | Out-Null
        }

        It 'Returns x64 for PE32+ files on disk' {
            $filePath = Join-Path -Path $Script:TestDirectory -ChildPath 'test64.dll'

            [byte[]]$pe = New-MinimalPE -Magic 0x20B

            [System.IO.File]::WriteAllBytes($filePath, $pe)

            $result = Get-PEArchitecture -Path $filePath

            $result | Should -BeExactly 'x64'
        }

        It 'Returns x86 for PE32 files on disk' {
            $filePath = Join-Path -Path  $Script:TestDirectory -ChildPath 'test32.dll'

            [byte[]]$pe = New-MinimalPE -Magic 0x10B

            [System.IO.File]::WriteAllBytes($filePath, $pe)

            $result = Get-PEArchitecture -Path $filePath

            $result | Should -BeExactly 'x86'
        }

        It 'Throws FileNotFoundException for non-existent files' {
            $nonExistentPath = Join-Path -Path $TestDrive -ChildPath 'does-not-exist.exe'

            { Get-PEArchitecture -Path $nonExistentPath } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
        }

        It 'Throws InvalidDataException for plain text files' {
            $filePath = Join-Path -Path $TestDrive -ChildPath 'not-a-pe.txt'

            Set-Content -Path $filePath -Value 'This is not a PE file.' -Encoding UTF8

            { Get-PEArchitecture -Path $filePath } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException])
        }

        It 'Throws when Path points to a directory' {
            $directoryPath = Join-Path -Path $TestDrive -ChildPath 'DirectoryOnly'

            New-Item -Path $directoryPath -ItemType Directory -Force | Out-Null

            { Get-PEArchitecture -Path $directoryPath } | Should -Throw
        }
    }

    Context 'Real system binaries' {

        It 'Detects the architecture of the running PowerShell process' {
            $pwshPath = (Get-Process -Id $PID).Path

            $result = Get-PEArchitecture -Path $pwshPath

            if ([Environment]::Is64BitProcess) {
                $result | Should -BeExactly 'x64'
            } else {
                $result | Should -BeExactly 'x86'
            }
        }
    }

    Context 'Invalid PE structures' {

        It 'Throws when byte array is null' {
            { Get-PEArchitecture -Bytes $null } | Should -Throw
        }

        It 'Throws when byte array is empty' {
            [byte[]]$bytes = @()

            { Get-PEArchitecture -Bytes $bytes } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException]) `
                -ExpectedMessage '*PE image buffer cannot be empty*'
        }

        It 'Throws when buffer is smaller than a DOS header' {
            [byte[]]$bytes = [byte[]]::new(63)

            { Get-PEArchitecture -Bytes $bytes } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException]) `
                -ExpectedMessage '*too small*'
        }

        It 'Throws when DOS header signature is missing' {
            [byte[]]$bytes = [byte[]]::new(256)

            { Get-PEArchitecture -Bytes $bytes } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException]) `
                -ExpectedMessage '*Missing DOS header signature*'
        }

        It 'Throws when e_lfanew points outside the buffer' {
            [byte[]]$pe = [byte[]]::new(128)

            $pe[0] = 0x4D
            $pe[1] = 0x5A

            [byte[]]$lfanew = [System.BitConverter]::GetBytes([UInt32]0xFF)
            [Array]::Copy($lfanew, 0, $pe, 0x3C, 4)

            { Get-PEArchitecture -Bytes $pe } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException]) `
                -ExpectedMessage '*Invalid PE header offset*'
        }

        It 'Throws when the PE signature is invalid' {
            [byte[]]$pe = [byte[]]::new(256)

            $pe[0] = 0x4D
            $pe[1] = 0x5A

            [byte[]]$lfanew = [System.BitConverter]::GetBytes([UInt32]0x80)
            [Array]::Copy($lfanew, 0, $pe, 0x3C, 4)

            # Invalid signature
            $pe[0x80] = 0x41
            $pe[0x81] = 0x42
            $pe[0x82] = 0x58
            $pe[0x83] = 0x58

            { Get-PEArchitecture -Bytes $pe } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException]) `
                -ExpectedMessage '*Missing PE signature*'
        }

        It 'Throws when the optional header is truncated' {
            [byte[]]$pe = [byte[]]::new(0x99)

            $pe[0] = 0x4D
            $pe[1] = 0x5A

            [byte[]]$lfanew = [System.BitConverter]::GetBytes([UInt32]0x80)
            [Array]::Copy($lfanew, 0, $pe, 0x3C, 4)

            $pe[0x80] = 0x50
            $pe[0x81] = 0x45
            $pe[0x82] = 0x00
            $pe[0x83] = 0x00

            { Get-PEArchitecture -Bytes $pe } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException]) `
                -ExpectedMessage '*Invalid PE header offset*'
        }

        It 'Throws when OptionalHeader.Magic exceeds buffer bounds' {
            [byte[]]$pe = [byte[]]::new(0x98)

            $pe[0] = 0x4D
            $pe[1] = 0x5A

            [byte[]]$lfanew = [System.BitConverter]::GetBytes([UInt32]0x80)
            [Array]::Copy($lfanew, 0, $pe, 0x3C, 4)

            $pe[0x80] = 0x50
            $pe[0x81] = 0x45
            $pe[0x82] = 0x00
            $pe[0x83] = 0x00

            { Get-PEArchitecture -Bytes $pe } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException])
        }
    }

    Context 'Output type' {

        It 'Returns System.String' {
            [byte[]]$pe = New-MinimalPE -Magic 0x20B

            $result = Get-PEArchitecture -Bytes $pe

            $result | Should -BeOfType ([string])
        }
    }
}
