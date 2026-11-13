#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Integration tests for Get-RegistryValue and Set-RegistryValue.

.DESCRIPTION
Verifies Get-RegistryValue and Set-RegistryValue against the real
Windows Registry under HKCU:\SOFTWARE\RDPControl\Tests. No mocks
are used.

These tests require Windows. No elevation is required.
When the required environment is unavailable, the suite is skipped.

The test key is created before each test and removed after each test.

Coverage includes:
  - Get-RegistryValue returns null when the key does not exist.
  - Get-RegistryValue returns null when the value does not exist.
  - Get-RegistryValue throws with Strict when the key does not exist.
  - Get-RegistryValue throws with Strict when the value does not exist.
  - Get-RegistryValue returns the correct value.
  - Set-RegistryValue creates the key and value when neither exists.
  - Set-RegistryValue is idempotent for DWord values.
  - Set-RegistryValue is idempotent for String values.
  - Set-RegistryValue updates an existing value.
  - Set-RegistryValue produces no pipeline output.
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

    $Script:SkipIntegration = -not $isWindowsPlatform
}

Describe 'Get-RegistryValue and Set-RegistryValue' -Tag 'Integration' -Skip:$Script:SkipIntegration {

    InModuleScope -ModuleName RDPControl {

        BeforeAll {

            $Script:TestKeyPath = 'HKCU:\SOFTWARE\RDPControl\Tests'
        }

        BeforeEach {

            if (Test-Path -LiteralPath $Script:TestKeyPath) {
                Remove-Item -LiteralPath $Script:TestKeyPath -Recurse -Force
            }

            New-Item -Path $Script:TestKeyPath -Force | Out-Null
        }

        AfterEach {

            if (Test-Path -LiteralPath $Script:TestKeyPath) {
                Remove-Item -LiteralPath $Script:TestKeyPath -Recurse -Force
            }
        }

        #region Get-RegistryValue
        Context 'Get-RegistryValue' {

            It 'Returns null when the key does not exist' {
                $getParams = @{
                    Path = 'HKCU:\SOFTWARE\RDPControl\Tests\Missing'
                    Name = 'Value'
                }

                $result = Get-RegistryValue @getParams

                $result | Should -BeNullOrEmpty
            }

            It 'Returns null when the value does not exist' {
                $getParams = @{
                    Path = $Script:TestKeyPath
                    Name = 'Missing'
                }

                $result = Get-RegistryValue @getParams

                $result | Should -BeNullOrEmpty
            }

            It 'Throws with Strict when the key does not exist' {
                $getParams = @{
                    Path   = 'HKCU:\SOFTWARE\RDPControl\Tests\Missing'
                    Name   = 'Value'
                    Strict = $true
                }

                { Get-RegistryValue @getParams } |
                    Should -Throw -ErrorId 'RegistryKeyNotFound,*'
            }

            It 'Throws with Strict when the value does not exist' {
                $getParams = @{
                    Path   = $Script:TestKeyPath
                    Name   = 'Missing'
                    Strict = $true
                }

                { Get-RegistryValue @getParams } |
                    Should -Throw -ErrorId 'RegistryValueNotFound,*'
            }

            It 'Returns the correct DWord value' {
                $setParams = @{
                    Path    = $Script:TestKeyPath
                    Name    = 'DWordValue'
                    Value   = 42
                    Type    = 'DWord'
                    Confirm = $false
                }

                Set-RegistryValue @setParams

                $result = Get-RegistryValue -Path $Script:TestKeyPath -Name 'DWordValue'

                $result | Should -Be 42
            }

            It 'Returns the correct String value' {
                $setParams = @{
                    Path    = $Script:TestKeyPath
                    Name    = 'StringValue'
                    Value   = 'RDPControl'
                    Type    = 'String'
                    Confirm = $false
                }

                Set-RegistryValue @setParams

                $result = Get-RegistryValue -Path $Script:TestKeyPath -Name 'StringValue'

                $result | Should -Be 'RDPControl'
            }
        }
        #endregion

        #region Set-RegistryValue
        Context 'Set-RegistryValue' {

            It 'Creates the key and value when neither exists' {
                Remove-Item -LiteralPath $Script:TestKeyPath -Recurse -Force

                $setParams = @{
                    Path    = $Script:TestKeyPath
                    Name    = 'NewValue'
                    Value   = 1
                    Type    = 'DWord'
                    Confirm = $false
                }

                { Set-RegistryValue @setParams } | Should -Not -Throw

                $result = Get-RegistryValue -Path $Script:TestKeyPath -Name 'NewValue'

                $result | Should -Be 1
            }

            It 'Is idempotent for DWord values' {
                $setParams = @{
                    Path    = $Script:TestKeyPath
                    Name    = 'DWordValue'
                    Value   = 1
                    Type    = 'DWord'
                    Confirm = $false
                }

                Set-RegistryValue @setParams

                { Set-RegistryValue @setParams } | Should -Not -Throw

                $result = Get-RegistryValue -Path $Script:TestKeyPath -Name 'DWordValue'

                $result | Should -Be 1
            }

            It 'Is idempotent for String values' {
                $setParams = @{
                    Path    = $Script:TestKeyPath
                    Name    = 'StringValue'
                    Value   = 'RDPControl'
                    Type    = 'String'
                    Confirm = $false
                }

                Set-RegistryValue @setParams

                { Set-RegistryValue @setParams } | Should -Not -Throw

                $result = Get-RegistryValue -Path $Script:TestKeyPath -Name 'StringValue'

                $result | Should -Be 'RDPControl'
            }

            It 'Updates an existing value' {
                $setParams = @{
                    Path    = $Script:TestKeyPath
                    Name    = 'DWordValue'
                    Value   = 1
                    Type    = 'DWord'
                    Confirm = $false
                }

                Set-RegistryValue @setParams

                $setParams.Value = 2

                Set-RegistryValue @setParams

                $result = Get-RegistryValue -Path $Script:TestKeyPath -Name 'DWordValue'

                $result | Should -Be 2
            }

            It 'Produces no pipeline output' {
                $setParams = @{
                    Path    = $Script:TestKeyPath
                    Name    = 'VoidValue'
                    Value   = 0
                    Type    = 'DWord'
                    Confirm = $false
                }

                $result = @(Set-RegistryValue @setParams)

                $result | Should -HaveCount 0
            }
        }
        #endregion
    }
}
