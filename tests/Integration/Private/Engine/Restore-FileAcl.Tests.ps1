#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Integration tests for Restore-FileAcl.

.DESCRIPTION
Verifies Restore-FileAcl against real files created in an isolated
TestDrive directory. No mocks are used.

These tests require Windows and an elevated PowerShell session.
When the required environment is unavailable, the suite is skipped.

Coverage includes:
  - Restores the original ACL without throwing.
  - Preserves the original access rules after restoration.
  - Produces no pipeline output.
  - Throws when the target file does not exist.
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
        $identity   = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal  = [System.Security.Principal.WindowsPrincipal]::new($identity)
        $isElevated = $principal.IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }

    $Script:SkipIntegration = -not ($isWindowsPlatform -and $isElevated)
}

Describe 'Restore-FileAcl' -Tag 'Integration' -Skip:$Script:SkipIntegration {

    InModuleScope -ModuleName RDPControl {

        #region ACL restoration
        Context 'ACL restoration' {

            It 'Restores the original ACL without throwing' {
                $file = Join-Path -Path $TestDrive -ChildPath 'restore.dll'

                Set-Content -LiteralPath $file -Value 'integration'

                $originalAcl = Get-Acl -LiteralPath $file -ErrorAction Stop

                {
                    $restoreParams = @{
                        Path    = $file
                        Acl     = $originalAcl
                        Confirm = $false
                    }

                    Restore-FileAcl @restoreParams
                } | Should -Not -Throw
            }

            It 'Preserves the original access rules after restoration' {
                $file = Join-Path -Path $TestDrive -ChildPath 'acl-check.dll'

                Set-Content -LiteralPath $file -Value 'integration'

                $originalAcl   = Get-Acl -LiteralPath $file -ErrorAction Stop
                $originalRules = $originalAcl.GetAccessRules(
                    $true, $true,
                    [System.Security.Principal.SecurityIdentifier]
                )

                $restoreParams = @{
                    Path    = $file
                    Acl     = $originalAcl
                    Confirm = $false
                }

                Restore-FileAcl @restoreParams

                $restoredAcl   = Get-Acl -LiteralPath $file -ErrorAction Stop

                $restoredRules = $restoredAcl.GetAccessRules(
                    $true, $true,
                    [System.Security.Principal.SecurityIdentifier]
                )

                $restoredRules.Count | Should -Be $originalRules.Count
            }
        }
        #endregion

        #region Return contract
        Context 'Return contract' {

            It 'Produces no pipeline output' {
                $file = Join-Path -Path $TestDrive -ChildPath 'void.dll'

                Set-Content -LiteralPath $file -Value 'integration'

                $acl = Get-Acl -LiteralPath $file -ErrorAction Stop

                $restoreParams = @{
                    Path    = $file
                    Acl     = $acl
                    Confirm = $false
                }

                $result = @(Restore-FileAcl @restoreParams)

                $result | Should -HaveCount 0
            }
        }
        #endregion

        #region Error handling
        Context 'Error handling' {

            It 'Throws when the target file does not exist' {
                $missingFile = Join-Path -Path $TestDrive -ChildPath 'missing.dll'

                $dummyFile   = Join-Path -Path $TestDrive -ChildPath 'dummy.dll'

                Set-Content -LiteralPath $dummyFile -Value 'integration'

                $acl = Get-Acl -LiteralPath $dummyFile -ErrorAction Stop

                $restoreParams = @{
                    Path    = $missingFile
                    Acl     = $acl
                    Confirm = $false
                }

                { Restore-FileAcl @restoreParams } |
                    Should -Throw -ErrorId 'RestoreAclFileNotFound,*'
            }
        }
        #endregion
    }
}
