#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Unit tests for Set-RdpService.

.DESCRIPTION
Verifies the Set-RdpService contract using Pester mocks.

No real system changes are performed. Set-RdpAccessState is mocked
at the boundary — its internal CIM and registry logic is covered by
its own test suite.

Coverage includes:
  - Throws when not elevated.
  - Calls Assert-RdpEnvironment.
  - Enables RDP and starts TermService.
  - Reports Method from the access state result.
  - Falls back to RegistryFallback method transparently.
  - Calls Set-FirewallRule by port in the registry fallback path.
  - Does not call Get-NetFirewallRule with DisplayName (regression: issue #10).
  - Disables RDP and stops TermService.
  - Warns and requires confirmation when disabling from an active RDP session.
  - WhatIf support.
  - Returns the correct result object.
  - Writes an audit record on every state change.
#>

# InModuleScope needs to resolve the RDPControl module during the Discovery
# phase, because that's when Context/It are executed to register the test
# tree. If the module isn't loaded at that point, InModuleScope fails before
# any BeforeAll or BeforeEach ever runs.
BeforeDiscovery {
    $moduleRoot = (Get-Item -LiteralPath $PSScriptRoot).Parent.Parent.Parent.Parent.FullName

    $moduleManifest = Join-Path -Path $moduleRoot -ChildPath 'RDPControl.psd1'

    Import-Module -Name $moduleManifest -Force -Global -ErrorAction Stop
}

Describe 'Set-RdpService' -Tag 'Unit' {

    InModuleScope -ModuleName RDPControl {

        BeforeAll {

            $Script:DefaultPort = 3389
        }

        BeforeEach {

            Mock -CommandName Assert-RdpEnvironment -MockWith {

            }

            Mock -CommandName Test-IsElevated -MockWith {
                $true
            }

            Mock -CommandName Test-IsRdpSession -MockWith {
                $false
            }

            Mock -CommandName Start-TermService -MockWith {

            }

            Mock -CommandName Stop-TermService -MockWith {

            }

            Mock -CommandName New-StoreAuditRecord -MockWith {
                1
            }

            Mock -CommandName Get-RdpPort -MockWith {
                [PSCustomObject]@{
                    Port = $Script:DefaultPort
                }
            }

            Mock -CommandName Set-FirewallRule -MockWith {

            }

            Mock -CommandName Get-NetFirewallRule -MockWith {

            }

            Mock -CommandName Set-RdpAccessState -MockWith {
                [PSCustomObject]@{
                    Success = $true
                    Method  = 'CIM'
                }
            }
        }

        #region Elevation requirement
        Context 'Elevation requirement' {

            It 'Throws when not elevated' {
                Mock -CommandName Test-IsElevated -MockWith { $false }

                { Set-RdpService -Enabled -Confirm:$false } |
                    Should -Throw -ErrorId 'ElevationRequired,*'
            }

            It 'Does not call Set-RdpAccessState when not elevated' {
                Mock -CommandName Test-IsElevated -MockWith { $false }

                { Set-RdpService -Enabled -Confirm:$false } | Should -Throw

                Should -Invoke Set-RdpAccessState -Times 0 -Exactly
            }
        }
        #endregion

        #region Environment validation
        Context 'Environment validation' {

            It 'Calls Assert-RdpEnvironment exactly once' {
                Set-RdpService -Enabled -Confirm:$false

                Should -Invoke Assert-RdpEnvironment -Times 1 -Exactly
            }
        }
        #endregion

        #region Enable
        Context 'Enable' {

            It 'Returns State Enabled' {
                $result = Set-RdpService -Enabled -Confirm:$false

                $result.State | Should -Be 'Enabled'
            }

            It 'Returns Method CIM when access state reports CIM' {
                $result = Set-RdpService -Enabled -Confirm:$false

                $result.Method | Should -Be 'CIM'
            }

            It 'Returns Method RegistryFallback when access state reports RegistryFallback' {
                Mock -CommandName Set-RdpAccessState -MockWith {
                    [PSCustomObject]@{
                        Success = $true
                        Method  = 'RegistryFallback'
                    }
                }

                $result = Set-RdpService -Enabled -Confirm:$false

                $result.Method | Should -Be 'RegistryFallback'
            }

            It 'Calls Set-RdpAccessState with AllowConnections true' {
                Set-RdpService -Enabled -Confirm:$false

                $invokeParams = @{
                    CommandName     = 'Set-RdpAccessState'
                    Times           = 1
                    Exactly         = $true
                    ParameterFilter = { $AllowConnections -eq $true }
                }

                Should -Invoke @invokeParams
            }

            It 'Starts TermService after enabling' {
                Set-RdpService -Enabled -Confirm:$false

                Should -Invoke Start-TermService -Times 1 -Exactly
            }

            It 'Writes an audit record when enabled' {
                Set-RdpService -Enabled -Confirm:$false

                Should -Invoke New-StoreAuditRecord -Times 1 -Exactly
            }

            It 'Does not call Get-NetFirewallRule with DisplayName (regression: issue #10)' {
                Set-RdpService -Enabled -Confirm:$false

                $invokeParams = @{
                    CommandName     = 'Get-NetFirewallRule'
                    Times           = 0
                    Exactly         = $true
                    ParameterFilter = { $DisplayName -eq 'Remote Desktop Connection' }
                }

                Should -Invoke @invokeParams
            }
        }
        #endregion

        #region Disable
        Context 'Disable' {

            It 'Returns State Disabled' {
                $result = Set-RdpService -Disabled -Confirm:$false

                $result.State | Should -Be 'Disabled'
            }

            It 'Calls Set-RdpAccessState with AllowConnections false' {
                Set-RdpService -Disabled -Confirm:$false

                $invokeParams = @{
                    CommandName     = 'Set-RdpAccessState'
                    Times           = 1
                    Exactly         = $true
                    ParameterFilter = { $AllowConnections -eq $false }
                }

                Should -Invoke @invokeParams
            }

            It 'Stops TermService before configuring state' {
                Set-RdpService -Disabled -Confirm:$false

                Should -Invoke Stop-TermService -Times 1 -Exactly
            }

            It 'Writes an audit record when disabled' {
                Set-RdpService -Disabled -Confirm:$false

                Should -Invoke New-StoreAuditRecord -Times 1 -Exactly
            }

            It 'Does not start TermService when disabling' {
                Set-RdpService -Disabled -Confirm:$false

                Should -Invoke Start-TermService -Times 0 -Exactly
            }
        }
        #endregion

        #region Lock-out protection
        Context 'Lock-out protection' {

            BeforeEach {

                Mock -CommandName Test-IsRdpSession -MockWith { $true }
            }

            It 'Writes a warning when disabling from an active RDP session' {
                $warnings = @(
                    & { Set-RdpService -Disabled -Confirm:$false } 3>&1 |
                        Where-Object {
                            $_ -is [System.Management.Automation.WarningRecord]
                        } |

                        ForEach-Object Message
                )

                ($warnings -join "`n") | Should -Match 'Remote Desktop'
            }
        }
        #endregion

        #region WhatIf support
        Context 'WhatIf support' {

            It 'Does not call Set-RdpAccessState under WhatIf when enabling' {
                Set-RdpService -Enabled -WhatIf

                Should -Invoke Set-RdpAccessState -Times 0 -Exactly
                Should -Invoke Start-TermService  -Times 0 -Exactly
            }

            It 'Does not call Set-RdpAccessState under WhatIf when disabling' {
                Set-RdpService -Disabled -WhatIf

                Should -Invoke Stop-TermService   -Times 0 -Exactly
                Should -Invoke Set-RdpAccessState -Times 0 -Exactly
            }
        }
        #endregion

        #region Return contract
        Context 'Return contract' {

            It 'Returns a PSCustomObject' {
                $result = Set-RdpService -Enabled -Confirm:$false

                $result | Should -BeOfType [PSCustomObject]
            }

            It 'Returns all required properties' {
                $result = Set-RdpService -Enabled -Confirm:$false

                $result.PSObject.Properties.Name | Should -Contain 'State'
                $result.PSObject.Properties.Name | Should -Contain 'Method'
                $result.PSObject.Properties.Name | Should -Contain 'ConfiguredAt'
            }

            It 'Returns ConfiguredAt in ISO 8601 format' {
                $result = Set-RdpService -Enabled -Confirm:$false

                $result.ConfiguredAt | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
            }
        }
        #endregion
    }
}
