#Requires -Version 5.1

BeforeAll {
    . "$RepositoryRoot/src/Private/Engine/Test-IsElevated.ps1"
    . "$RepositoryRoot/src/Private/Engine/Grant-ProtectedFileAccess.ps1"
}

Describe 'Grant-ProtectedFileAccess' {

    Context 'Elevation validation' {

        BeforeEach {
            Mock Test-IsElevated { $false }
        }

        It 'Throws when process is not elevated' {
            $file = Join-Path -Path $TestDrive -ChildPath 'test.dll'

            Set-Content -LiteralPath $file -Value 'data'

            { Grant-ProtectedFileAccess -Path $file } |
                Should -Throw -ErrorId 'GrantProtectedFileAccessFailed,Grant-ProtectedFileAccess'
        }
    }

    Context 'Path validation' {

        BeforeEach {
            Mock Test-IsElevated { $true }
        }

        It 'Throws ProtectedFileNotFound when file does not exist' {
            $missing = Join-Path -Path $TestDrive -ChildPath 'missing.dll'

            { Grant-ProtectedFileAccess -Path $missing } |
                Should -Throw -ErrorId 'ProtectedFileNotFound,Grant-ProtectedFileAccess'
        }

        It 'Throws ProtectedFileNotFound when path is a directory' {
            { Grant-ProtectedFileAccess -Path $TestDrive } |
                Should -Throw -ErrorId 'ProtectedFileNotFound,Grant-ProtectedFileAccess'
        }
    }

    Context 'Resolve-Path failures' {

        BeforeEach {
            Mock Test-IsElevated { $true }

            Mock Test-Path { $true }

            Mock Resolve-Path {
                throw [System.IO.IOException]::new('Resolve failure')
            }
        }

        It 'Wraps Resolve-Path exceptions' {

            { Grant-ProtectedFileAccess -Path 'C:\Fake.dll' } |
                Should -Throw -ErrorId 'GrantProtectedFileAccessFailed,Grant-ProtectedFileAccess'
        }
    }

    Context 'Error contract' {

        BeforeEach {
            Mock Test-IsElevated { $false }
        }

        It 'Returns PermissionDenied category for elevation failures' {
            try {
                Grant-ProtectedFileAccess -Path 'C:\Fake.dll'
            } catch {
                $_.CategoryInfo.Category | Should -Be 'PermissionDenied'
            }
        }

        It 'Uses GrantProtectedFileAccessFailed error id for wrapped failures' {
            try {
                Grant-ProtectedFileAccess -Path 'C:\Fake.dll'
            } catch {
                $_.FullyQualifiedErrorId |
                    Should -Match 'GrantProtectedFileAccessFailed'
            }
        }
    }

    Context 'Parameter validation' {

        It 'Rejects null path' {
            { Grant-ProtectedFileAccess -Path $null } | Should -Throw
        }

        It 'Rejects empty path' {
            { Grant-ProtectedFileAccess -Path '' } | Should -Throw
        }
    }

    Context 'Return value' {

        BeforeEach {
            Mock Test-IsElevated { $false }
        }

        It 'Produces no pipeline output' {
            $file = Join-Path -Path $TestDrive -ChildPath 'test.dll'
            Set-Content -LiteralPath $file -Value 'abc'

            $result = try {
                Grant-ProtectedFileAccess -Path $file -ErrorAction SilentlyContinue
            } catch {
                $null
            }

            $result | Should -BeNullOrEmpty
        }
    }
}
