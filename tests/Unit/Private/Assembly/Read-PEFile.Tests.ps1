Describe 'Read-PEFile' {

    BeforeAll {

        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-PEArchitecture.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Read-PEFile.ps1"

        function New-MinimalPE {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions',
                '',
                Justification = 'Internal test helper.'
            )]
            param (
                [Parameter(Mandatory)]
                [UInt16]$Magic
            )

            [byte[]]$pe = [byte[]]::new(256)

            #
            # IMAGE_DOS_HEADER
            #

            # MZ
            $pe[0] = 0x4D
            $pe[1] = 0x5A

            # e_lfanew -> 0x80
            [byte[]]$lfanew = [System.BitConverter]::GetBytes([UInt32]0x80)

            [System.Array]::Copy($lfanew, 0, $pe, 0x3C, 4)

            #
            # IMAGE_NT_HEADERS
            #

            # PE\0\0
            $pe[0x80] = 0x50
            $pe[0x81] = 0x45
            $pe[0x82] = 0x00
            $pe[0x83] = 0x00

            #
            # IMAGE_OPTIONAL_HEADER.Magic
            #

            [byte[]]$magicBytes = [System.BitConverter]::GetBytes($Magic)

            [System.Array]::Copy($magicBytes, 0, $pe, 0x98, 2)

            return $pe
        }

        $Script:TestDirectory = Join-Path -Path $TestDrive -ChildPath 'ReadPEFile'

        New-Item -Path $Script:TestDirectory -ItemType Directory -Force | Out-Null

        #
        # x64 image
        #

        $Script:x64Path = Join-Path -Path $Script:TestDirectory -ChildPath 'test64.dll'

        [byte[]]$x64Bytes = New-MinimalPE -Magic 0x20B

        [System.IO.File]::WriteAllBytes($Script:x64Path, $x64Bytes)

        #
        # x86 image
        #

        $Script:x86Path = Join-Path -Path $Script:TestDirectory -ChildPath 'test32.dll'

        [byte[]]$x86Bytes = New-MinimalPE -Magic 0x10B

        [System.IO.File]::WriteAllBytes($Script:x86Path, $x86Bytes)

        #
        # ROM image
        #

        $Script:romPath = Join-Path -Path $Script:TestDirectory -ChildPath 'testrom.dll'

        [byte[]]$romBytes = New-MinimalPE -Magic 0x107

        [System.IO.File]::WriteAllBytes($script:romPath, $romBytes)
    }

    Context 'Output structure' {

        It 'Returns a PSCustomObject' {
            $result = Read-PEFile -Path $Script:x64Path

            $result | Should -BeOfType ([pscustomobject])
        }

        It 'Returns Bytes, Architecture and Path properties' {
            $result = Read-PEFile -Path $Script:x64Path

            $result.PSObject.Properties.Name | Should -Contain 'Bytes'

            $result.PSObject.Properties.Name | Should -Contain 'Architecture'

            $result.PSObject.Properties.Name | Should -Contain 'Path'
        }

        It 'Returns Bytes as byte array' {
            $result = Read-PEFile -Path $Script:x64Path

            $result.Bytes.GetType() | Should -Be ([byte[]])
        }

        It 'Returns Architecture as string' {
            $result = Read-PEFile -Path $Script:x64Path

            $result.Architecture | Should -BeOfType ([string])
        }

        It 'Returns Path as string' {
            $result = Read-PEFile -Path $Script:x64Path

            $result.Path | Should -BeOfType ([string])
        }

        It 'Returns a typed PE object' {
            $result = Read-PEFile -Path $Script:x64Path

            $result.PSTypeNames | Should -Contain 'RDPControl.PEFile'
        }

        It 'Registers RDPControl.PEFile as the primary PSTypeName' {
            $result = Read-PEFile -Path $Script:x64Path

            $result.PSTypeNames[0] | Should -BeExactly 'RDPControl.PEFile'
        }
    }

    Context 'Byte reading' {

        It 'Reads the correct number of bytes' {
            $result = Read-PEFile -Path $Script:x64Path

            $result.Bytes.Length | Should -BeExactly 256
        }

        It 'Returns bytes identical to the file contents' {
            $result = Read-PEFile -Path $Script:x64Path

            [byte[]]$expected = [System.IO.File]::ReadAllBytes($Script:x64Path)

            [System.Linq.Enumerable]::SequenceEqual($result.Bytes, $expected) |
                Should -BeTrue
        }

        It 'Returns a non-null byte array' {
            $result = Read-PEFile -Path $Script:x64Path

            $result.Bytes | Should -Not -BeNullOrEmpty
        }

        It 'Returns an independent byte array instance' {
            $result = Read-PEFile -Path $Script:x64Path

            [byte[]]$original = [System.IO.File]::ReadAllBytes($Script:x64Path)

            $result.Bytes[0] = 0x00

            $original[0] | Should -BeExactly 0x4D
        }

        It 'Reads files currently opened by another stream' {
            $stream = [System.IO.File]::Open(
                $Script:x64Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )

            try {
                $result = Read-PEFile -Path $Script:x64Path

                $result.Bytes.Length | Should -BeGreaterThan 0
            } finally {

                $stream.Dispose()
            }
        }
    }

    Context 'Architecture detection' {

        It 'Detects x64 PE images correctly' {
            $result = Read-PEFile -Path $Script:x64Path

            $result.Architecture | Should -BeExactly 'x64'
        }

        It 'Detects x86 PE images correctly' {
            $result = Read-PEFile -Path $script:x86Path

            $result.Architecture | Should -BeExactly 'x86'
        }

        It 'Detects ROM PE images correctly' {
            $result = Read-PEFile -Path $script:romPath

            $result.Architecture | Should -BeExactly 'ROM'
        }
    }

    Context 'Path handling' {

        It 'Returns the fully resolved path' {
            $result = Read-PEFile -Path $Script:x64Path

            $expected = (Resolve-Path -LiteralPath $Script:x64Path).ProviderPath

            $result.Path | Should -BeExactly $expected
        }

        It 'Accepts relative paths' {
            Push-Location $Script:TestDirectory

            try {
                $result = Read-PEFile -Path '.\test64.dll'

                $result.Architecture | Should -BeExactly 'x64'
            } finally {
                Pop-Location
            }
        }

        It 'Resolves provider-qualified paths correctly' {
            $resolvedPath = Resolve-Path -LiteralPath $Script:x64Path

            $result = Read-PEFile -Path $resolvedPath

            $result.Path | Should -BeExactly $resolvedPath.ProviderPath
        }
    }

    Context 'Internal integration' {

        It 'Uses Get-PEArchitecture for architecture detection' {
            Mock Get-PEArchitecture { return 'MOCK' }

            $result = Read-PEFile -Path $Script:x64Path

            $result.Architecture | Should -BeExactly 'MOCK'

            Should -Invoke -CommandName Get-PEArchitecture -Times 1 -Exactly
        }
    }

    Context 'File errors' {

        It 'Throws FileNotFoundException for missing files' {
            { Read-PEFile -Path 'C:\Does\Not\Exist.dll' } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
        }

        It 'Throws when Path points to a directory' {
            { Read-PEFile -Path $Script:TestDirectory } | Should -Throw
        }

        It 'Throws InvalidDataException for empty files' {
            $emptyPath = Join-Path -Path $TestDrive -ChildPath 'empty.dll'

            [System.IO.File]::WriteAllBytes($emptyPath, [byte[]]@())

            { Read-PEFile -Path $emptyPath } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException]) `
                -ExpectedMessage '*empty*'
        }

        It 'Throws InvalidDataException for plain text files' {
            $textPath = Join-Path -Path $TestDrive -ChildPath 'not-a-pe.txt'

            [System.IO.File]::WriteAllBytes(
                $textPath,
                [System.Text.Encoding]::ASCII.GetBytes('This is not a PE file.')
            )

            { Read-PEFile -Path $textPath } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException]) `
                -ExpectedMessage '*DOS header*'
        }
    }

    Context 'Malformed PE structures' {

        It 'Throws for truncated PE images' {
            [byte[]]$truncated = [byte[]]::new(128)

            $truncated[0] = 0x4D
            $truncated[1] = 0x5A

            [byte[]]$lfanew = [System.BitConverter]::GetBytes([UInt32]0x80)

            [System.Array]::Copy($lfanew, 0, $truncated, 0x3C, 4)

            $truncatedPath = Join-Path -Path $TestDrive -ChildPath 'truncated.dll'

            [System.IO.File]::WriteAllBytes($truncatedPath, $truncated)

            { Read-PEFile -Path $truncatedPath } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException])
        }
    }

    Context 'Real system binaries' {

        It 'Reads the running PowerShell executable successfully' {
            $pwshPath = (Get-Process -Id $PID).Path

            $result = Read-PEFile -Path $pwshPath

            $result.Bytes.Length | Should -BeGreaterThan 0

            $result.Path | Should -BeExactly $pwshPath

            $expectedArchitecture = if ([System.Environment]::Is64BitProcess) {
                'x64'
            } else {
                'x86'
            }

            $result.Architecture | Should -BeExactly $expectedArchitecture
        }
    }
}
