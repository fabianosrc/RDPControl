Describe 'Get-BinaryVersion' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BinaryVersion.ps1"

        # PowerShell executable used as a stable real-world binary target
        $Script:TestBinary = (Get-Process -Id $PID).Path

        function Get-ExpectedVersion {
            param (
                [Parameter(Mandatory)]
                [string]$Path
            )

            $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)

            return [System.Version]::new(
                $info.FileMajorPart,
                $info.FileMinorPart,
                $info.FileBuildPart,
                $info.FilePrivatePart
            )
        }
    }

    Context 'Valid binary with version info' {

        It 'Returns a PSCustomObject' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result | Should -BeOfType [pscustomobject]
        }

        It 'Returns all expected properties' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $properties = $result.PSObject.Properties.Name

            $properties | Should -Contain 'Path'
            $properties | Should -Contain 'FileVersion'
            $properties | Should -Contain 'ProductVersion'
            $properties | Should -Contain 'NormalizedVersion'
        }

        It 'Returns the fully resolved absolute path' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $expected = (Resolve-Path -LiteralPath $Script:TestBinary).ProviderPath

            $result.Path | Should -Be $expected
        }

        It 'Returns FileVersion as a normalized version string' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.FileVersion | Should -Match '^\d+\.\d+\.\d+\.\d+$'
        }

        It 'Returns ProductVersion as a non-empty string' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.ProductVersion | Should -Not -BeNullOrEmpty
        }

        It 'Returns NormalizedVersion as System.Version' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.NormalizedVersion | Should -BeOfType [System.Version]
        }

        It 'Returns NormalizedVersion matching FileVersion' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.NormalizedVersion.ToString() | Should -Be $result.FileVersion
        }

        It 'Returns trimmed version strings without surrounding whitespace' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.FileVersion | Should -Be $result.FileVersion.Trim()

            $result.ProductVersion | Should -Be $result.ProductVersion.Trim()
        }

        It 'Returns culture-independent version formatting' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.NormalizedVersion.ToString() | Should -Match '^\d+\.\d+\.\d+\.\d+$'
        }
    }

    Context 'Consistency with FileVersionInfo API' {

        It 'Returns FileVersion matching FileVersionInfo components' {
            $expected = Get-ExpectedVersion -Path $Script:TestBinary

            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.FileVersion | Should -Be $expected.ToString()
        }

        It 'Returns NormalizedVersion matching FileVersionInfo components' {
            $expected = Get-ExpectedVersion -Path $Script:TestBinary

            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.NormalizedVersion.ToString() | Should -Be $expected.ToString()
        }
    }

    Context 'Path resolution' {

        It 'Accepts relative paths' {
            Push-Location (Split-Path $Script:TestBinary)

            try {
                $relativePath = Split-Path $Script:TestBinary -Leaf

                $result = Get-BinaryVersion -Path $relativePath

                $expected = (Resolve-Path $Script:TestBinary).ProviderPath

                $result.Path | Should -Be $expected
            } finally {
                Pop-Location
            }
        }

        It 'Accepts literal full paths' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.Path | Should -Be (Resolve-Path $Script:TestBinary).ProviderPath
        }
    }

    Context 'Determinism and consistency' {

        It 'Returns identical values across repeated executions' {
            $result1 = Get-BinaryVersion -Path $Script:TestBinary
            $result2 = Get-BinaryVersion -Path $Script:TestBinary

            $result1.FileVersion | Should -Be $result2.FileVersion

            $result1.ProductVersion | Should -Be $result2.ProductVersion

            $result1.NormalizedVersion.ToString() | Should -Be $result2.NormalizedVersion.ToString()
        }

        It 'Does not mutate returned version values between calls' {
            $first = Get-BinaryVersion -Path $Script:TestBinary
            $second = Get-BinaryVersion -Path $Script:TestBinary

            $first.FileVersion | Should -Be $second.FileVersion
        }
    }

    Context 'File not found' {

        It 'Throws when the specified file does not exist' {
            { Get-BinaryVersion -Path 'C:\nonexistent\fake.dll' } | Should -Throw
        }

        It 'Throws when path points to a directory' {
            $directory = Join-Path $TestDrive 'emptydir'

            New-Item -Path $directory -ItemType Directory -Force | Out-Null

            { Get-BinaryVersion -Path $directory } | Should -Throw
        }
    }

    Context 'Files without version metadata' {

        It 'Throws when the file has no embedded version information' {
            $file = Join-Path $TestDrive 'noversion.txt'

            Set-Content -Path $file -Value 'plain text' -Encoding UTF8

            { Get-BinaryVersion -Path $file } | Should -Throw
        }
    }

    Context 'Output structure' {

        It 'Has PSTypeName RDPControl.BinaryVersion' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.PSTypeNames | Should -Contain 'RDPControl.BinaryVersion'
        }

        It 'Returns exactly one normalized version object' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            @($result.NormalizedVersion) | Should -HaveCount 1
        }

        It 'Returns FileVersion as a string' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.FileVersion | Should -BeOfType [string]
        }

        It 'Returns ProductVersion as a string' {
            $result = Get-BinaryVersion -Path $Script:TestBinary

            $result.ProductVersion | Should -BeOfType [string]
        }
    }
}
