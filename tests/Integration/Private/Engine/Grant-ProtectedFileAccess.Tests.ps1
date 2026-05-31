#Requires -Version 5.1

. "$PSScriptRoot/../../../Bootstrap.ps1"

BeforeAll {
    . "$RepositoryRoot/src/Private/Engine/Test-IsElevated.ps1"

    if (-not ('RDPControl.PrivilegeScope' -as [type])) {
        throw 'RDPControl.PrivilegeScope type is not loaded.'
    }

    if (-not (Test-IsElevated)) {
        throw 'Integration tests must be executed from an elevated PowerShell session.'
    }
}

InModuleScope RDPControl {

    BeforeAll {
        $Script:CurrentUserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    }

    Describe 'Grant-ProtectedFileAccess Integration' -Tag 'Integration' {

        Context 'Privilege acquisition' {

            It 'Can acquire SeTakeOwnershipPrivilege' {
                $scope = [RDPControl.PrivilegeScope]::new('SeTakeOwnershipPrivilege')

                try {
                    $scope | Should -Not -BeNullOrEmpty
                } finally {
                    $scope.Dispose()
                }
            }
        }

        Context 'Access grant' {

            It 'Grants access without throwing' {
                $file = Join-Path -Path $TestDrive -ChildPath 'grant.dll'
                Set-Content -LiteralPath $file -Value 'integration'

                { Grant-ProtectedFileAccess -Path $file } | Should -Not -Throw
            }

            It 'Leaves the file accessible after access grant' {
                $file = Join-Path -Path $TestDrive -ChildPath 'readable.dll'
                Set-Content -LiteralPath $file -Value 'integration'

                Grant-ProtectedFileAccess -Path $file

                { Get-Content -LiteralPath $file -ErrorAction Stop } | Should -Not -Throw
            }

            It 'Grants FullControl to the current user' {
                $file = Join-Path -Path $TestDrive -ChildPath 'acl.dll'
                Set-Content -LiteralPath $file -Value 'integration'

                Grant-ProtectedFileAccess -Path $file

                $acl = Get-Acl -LiteralPath $file

                $rule = $acl.Access |
                    Where-Object {
                        $_.IdentityReference.Value -eq $Script:CurrentUserName
                    } |
                    Where-Object {
                        $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow
                    } |
                    Select-Object -First 1

                $rule | Should -Not -BeNullOrEmpty

                $rule.FileSystemRights.HasFlag(
                    [System.Security.AccessControl.FileSystemRights]::FullControl
                ) | Should -BeTrue
            }
        }

        Context 'Owner restoration' {

            It 'Restores original owner when RestoreOwner is specified' {
                $file = Join-Path -Path $TestDrive -ChildPath 'restore.dll'
                Set-Content -LiteralPath $file -Value 'integration'

                $originalOwner = (
                    Get-Acl -LiteralPath $file
                ).GetOwner(
                    [System.Security.Principal.SecurityIdentifier]
                )

                Grant-ProtectedFileAccess -Path $file -RestoreOwner

                $ownerAfter = (
                    Get-Acl -LiteralPath $file
                ).GetOwner(
                    [System.Security.Principal.SecurityIdentifier]
                )

                $ownerAfter.Value | Should -Be $originalOwner.Value
            }

            It 'Completes successfully when RestoreOwner is specified' {
                $file = Join-Path -Path $TestDrive -ChildPath 'restore-success.dll'
                Set-Content -LiteralPath $file -Value 'integration'

                { Grant-ProtectedFileAccess -Path $file -RestoreOwner } | Should -Not -Throw
            }
        }

        Context 'Function contract' {

            It 'Returns no output' {
                $file = Join-Path -Path $TestDrive -ChildPath 'void.dll'
                Set-Content -LiteralPath $file -Value 'integration'

                $result = Grant-ProtectedFileAccess -Path $file

                $result | Should -BeNullOrEmpty
            }

            It 'Returns no output when RestoreOwner is specified' {
                $file = Join-Path -Path $TestDrive -ChildPath 'void-restore.dll'
                Set-Content -LiteralPath $file -Value 'integration'

                $result = Grant-ProtectedFileAccess -Path $file -RestoreOwner

                $result | Should -BeNullOrEmpty
            }
        }

        Context 'Error handling' {

            It 'Throws when the target file does not exist' {
                {
                    Grant-ProtectedFileAccess -Path (
                        Join-Path -Path $TestDrive -ChildPath 'missing.dll'
                    )
                } | Should -Throw
            }
        }
    }
}
