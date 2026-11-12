#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Unit tests for Test-FirewallRuleCompliant.

.DESCRIPTION
Covers rule count validation, rule state validation and port filter
validation against a desired state object.

No real firewall query is performed by these tests. All calls to
Get-RulePortFilter are intercepted via Mock.

Coverage includes:
  - Returns false when no rules exist.
  - Returns false when multiple rules exist.
  - Returns false when the rule is disabled.
  - Returns false when the rule direction is Outbound.
  - Returns false when the rule action is Block.
  - Returns false when the port filter is null.
  - Returns false when the protocol differs from the desired state.
  - Returns false when the port differs from the desired state.
  - Returns false when multiple ports are bound to the rule.
  - Returns true when the rule fully matches the desired state.
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

Describe 'Test-FirewallRuleCompliant' -Tag 'Unit' {

    InModuleScope -ModuleName RDPControl {

        BeforeAll {

            $Script:DesiredState = @{
                Direction = 'Inbound'
                Action    = 'Allow'
                Enabled   = 'True'
                Protocol  = 'TCP'
                LocalPort = '3389'
            }

            $Script:CompliantRule = [PSCustomObject]@{
                Enabled   = 'True'
                Direction = 'Inbound'
                Action    = 'Allow'
            }
        }

        BeforeEach {

            Mock -CommandName Get-RulePortFilter -MockWith {
                [PSCustomObject]@{
                    Protocol  = 'TCP'
                    LocalPort = '3389'
                }
            }
        }

        #region Rule count validation
        Context 'Rule count validation' {

            It 'Returns false when no rules exist' {
                $params = @{
                    Rules        = @()
                    DesiredState = $Script:DesiredState
                }

                Test-FirewallRuleCompliant @params | Should -BeFalse
            }

            It 'Returns false when multiple rules exist' {
                $params = @{
                    Rules        = @(
                        [PSCustomObject]@{ }
                        [PSCustomObject]@{ }
                    )
                    DesiredState = $Script:DesiredState
                }

                Test-FirewallRuleCompliant @params | Should -BeFalse
            }
        }
        #endregion

        #region Rule state validation
        Context 'Rule state validation' {

            It 'Returns false when the rule is disabled' {
                $params = @{
                    Rules        = @(
                        [PSCustomObject]@{
                            Enabled   = 'False'
                            Direction = 'Inbound'
                            Action    = 'Allow'
                        }
                    )
                    DesiredState = $Script:DesiredState
                }

                Test-FirewallRuleCompliant @params | Should -BeFalse
            }

            It 'Returns false when the rule direction is Outbound' {
                $params = @{
                    Rules        = @(
                        [PSCustomObject]@{
                            Enabled   = 'True'
                            Direction = 'Outbound'
                            Action    = 'Allow'
                        }
                    )
                    DesiredState = $Script:DesiredState
                }

                Test-FirewallRuleCompliant @params | Should -BeFalse
            }

            It 'Returns false when the rule action is Block' {
                $params = @{
                    Rules        = @(
                        [PSCustomObject]@{
                            Enabled   = 'True'
                            Direction = 'Inbound'
                            Action    = 'Block'
                        }
                    )
                    DesiredState = $Script:DesiredState
                }

                Test-FirewallRuleCompliant @params | Should -BeFalse
            }
        }
        #endregion

        #region Port filter validation
        Context 'Port filter validation' {

            It 'Returns false when the port filter is null' {
                Mock -CommandName Get-RulePortFilter -MockWith {
                    $null
                }

                $params = @{
                    Rules        = @($Script:CompliantRule)
                    DesiredState = $Script:DesiredState
                }

                Test-FirewallRuleCompliant @params | Should -BeFalse
            }

            It 'Returns false when the protocol differs from the desired state' {
                Mock -CommandName Get-RulePortFilter -MockWith {
                    [PSCustomObject]@{
                        Protocol  = 'UDP'
                        LocalPort = '3389'
                    }
                }

                $params = @{
                    Rules        = @($Script:CompliantRule)
                    DesiredState = $Script:DesiredState
                }

                Test-FirewallRuleCompliant @params | Should -BeFalse
            }

            It 'Returns false when the port differs from the desired state' {
                Mock -CommandName Get-RulePortFilter -MockWith {
                    [PSCustomObject]@{
                        Protocol  = 'TCP'
                        LocalPort = '3390'
                    }
                }

                $params = @{
                    Rules        = @($Script:CompliantRule)
                    DesiredState = $Script:DesiredState
                }

                Test-FirewallRuleCompliant @params | Should -BeFalse
            }

            It 'Returns false when multiple ports are bound to the rule' {
                Mock -CommandName Get-RulePortFilter -MockWith {
                    [PSCustomObject]@{
                        Protocol  = 'TCP'
                        LocalPort = @('3388', '3389')
                    }
                }

                $params = @{
                    Rules        = @($Script:CompliantRule)
                    DesiredState = $Script:DesiredState
                }

                Test-FirewallRuleCompliant @params | Should -BeFalse
            }
        }
        #endregion

        #region Positive validation
        Context 'Positive validation' {

            It 'Returns true when the rule fully matches the desired state' {
                $params = @{
                    Rules        = @($Script:CompliantRule)
                    DesiredState = $Script:DesiredState
                }

                Test-FirewallRuleCompliant @params | Should -BeTrue
            }
        }
        #endregion
    }
}
