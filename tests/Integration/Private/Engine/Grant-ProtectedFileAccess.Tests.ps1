
#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Integration tests for Grant-ProtectedFileAccess.

.DESCRIPTION
Verifies Grant-ProtectedFileAccess against real files created in an
isolated TestDrive directory. No mocks are used.

These tests require Windows and an elevated PowerShell session.
When the required environment is unavailable, the suite is skipped.

Coverage includes:
  - Acquires SeTakeOwnershipPrivilege.
  - Grants access to an existing file without throwing.
  - Preserves file readability.
  - Grants FullControl to the current user.
  - Restores the original owner when RestoreOwner is specified.
  - Completes successfully with RestoreOwner.
  - Produces no pipeline output.
  - Produces no pipeline output with RestoreOwner.
  - Throws when the target file does not exist.

.NOTES
These tests modify ACLs only on temporary files under TestDrive.
They do not modify protected Windows system files.
#>

# InModuleScope needs to resolve the PipeDFe module during the Discovery phase,
# because that's when Context/It are executed to register the test tree. If the
# module isn't loaded at that point, InModuleScope fails before any BeforeAll or
# BeforeEach ever runs.
BeforeDiscovery {
    $moduleRoot = (Get-Item -LiteralPath $PSScriptRoot).Parent.Parent.Parent.Parent.FullName

    $moduleManifest = Join-Path -Path $moduleRoot -ChildPath 'RDPControl.psd1'

    Import-Module -Name $moduleManifest -Force -Global -ErrorAction Stop

    $isWindowsPlatform = (
        [System.Environment]::OSVersion.Platform -eq
        [System.PlatformID]::Win32NT
    )

    $isElevated = $false

    if ($isWindowsPlatform) {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

        $principal = [System.Security.Principal.WindowsPrincipal]::new(
            $identity
        )

        $isElevated = $principal.IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }

    $Script:SkipIntegration = -not ($isWindowsPlatform -and $isElevated)
}

Describe 'Grant-ProtectedFileAccess' -Tag 'Integration' -Skip:$Script:SkipIntegration {

    InModuleScope -ModuleName RDPControl {

        BeforeAll {

            if (-not ('RDPControl.PrivilegeScope' -as [type])) {
                throw 'RDPControl.PrivilegeScope type is not loaded.'
            }

            if (-not (Test-IsElevated)) {
                throw 'Integration tests require an elevated PowerShell session.'
            }

            $Script:CurrentIdentity = (
                [System.Security.Principal.WindowsIdentity]::GetCurrent()
            )

            $Script:CurrentUserSid = $Script:CurrentIdentity.User.Value
        }

        #region Privilege acquisition
        Context 'Privilege acquisition' {

            It 'Can acquire SeTakeOwnershipPrivilege' {
                $scope = $null

                try {
                    $scope = [RDPControl.PrivilegeScope]::new(
                        'SeTakeOwnershipPrivilege'
                    )

                    $scope | Should -Not -BeNullOrEmpty
                } finally {
                    if ($null -ne $scope) {
                        $scope.Dispose()
                    }
                }
            }
        }
        #endregion

        #region Access grant
        Context 'Access grant' {

            It 'Completes without throwing for an existing file' {
                $file = Join-Path -Path $TestDrive -ChildPath 'grant.dll'

                Set-Content -LiteralPath $file -Value 'integration'

                { Grant-ProtectedFileAccess -Path $file } | Should -Not -Throw
            }

            It 'Leaves the file readable after granting access' {
                $file = Join-Path -Path $TestDrive -ChildPath 'readable.dll'

                Set-Content -LiteralPath $file -Value 'integration'

                Grant-ProtectedFileAccess -Path $file

                $content = Get-Content -LiteralPath $file -Raw -ErrorAction Stop

                $content | Should -Match 'integration'
            }

            It 'Grants FullControl to the current user' {
                $file = Join-Path -Path $TestDrive -ChildPath 'acl.dll'

                Set-Content -LiteralPath $file -Value 'integration'

                Grant-ProtectedFileAccess -Path $file

                $acl = Get-Acl -LiteralPath $file -ErrorAction Stop

                $allowRules = @(
                    $acl.GetAccessRules(
                        $true,
                        $true,
                        [System.Security.Principal.SecurityIdentifier]
                    ) | Where-Object {
                            $_.IdentityReference.Value -eq $Script:CurrentUserSid -and
                            $_.AccessControlType -eq (
                                [System.Security.AccessControl.AccessControlType]::Allow
                            )
                    }
                )

                $allowRules | Should -Not -BeNullOrEmpty

                $fullControl = (
                    [System.Security.AccessControl.FileSystemRights]::FullControl
                )

                $hasFullControl = @(
                    $allowRules |
                        Where-Object {
                            ($_.FileSystemRights -band $fullControl) -eq $fullControl
                        }
                ).Count -gt 0

                $hasFullControl | Should -BeTrue
            }
        }
        #endregion

        #region Owner restoration
        Context 'Owner restoration' {

            It 'Restores the original owner when RestoreOwner is specified' {
                $file = Join-Path -Path $TestDrive -ChildPath 'restore.dll'

                Set-Content -LiteralPath $file -Value 'integration'

                $originalOwner = (
                    Get-Acl -LiteralPath $file -ErrorAction Stop
                ).GetOwner(
                    [System.Security.Principal.SecurityIdentifier]
                )

                Grant-ProtectedFileAccess -Path $file -RestoreOwner

                $ownerAfter = (
                    Get-Acl -LiteralPath $file -ErrorAction Stop
                ).GetOwner(
                    [System.Security.Principal.SecurityIdentifier]
                )

                $ownerAfter.Value | Should -Be $originalOwner.Value
            }

            It 'Completes without throwing when RestoreOwner is specified' {
                $file = Join-Path -Path $TestDrive -ChildPath 'restore-success.dll'

                Set-Content -LiteralPath $file -Value 'integration'

                { Grant-ProtectedFileAccess -Path $file -RestoreOwner } |
                    Should -Not -Throw
            }
        }
        #endregion

        #region Return contract
        Context 'Return contract' {

            It 'Produces no pipeline output' {
                $file = Join-Path -Path $TestDrive -ChildPath 'void.dll'

                Set-Content -LiteralPath $file -Value 'integration'

                $result = @(Grant-ProtectedFileAccess -Path $file)

                $result | Should -HaveCount 0
            }

            It 'Produces no pipeline output with RestoreOwner' {
                $file = Join-Path -Path $TestDrive -ChildPath 'void-restore.dll'

                Set-Content -LiteralPath $file -Value 'integration'

                $result = @(Grant-ProtectedFileAccess -Path $file -RestoreOwner)

                $result | Should -HaveCount 0
            }
        }
        #endregion

        #region Error handling
        Context 'Error handling' {

            It 'Throws when the target file does not exist' {
                $missingFile = Join-Path -Path $TestDrive -ChildPath 'missing.dll'

                Test-Path -LiteralPath $missingFile | Should -BeFalse

                { Grant-ProtectedFileAccess -Path $missingFile } | Should -Throw
            }
        }
        #endregion
    }
}
