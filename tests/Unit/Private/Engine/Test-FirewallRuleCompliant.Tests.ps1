#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-RulePortFilter.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Test-FirewallRuleCompliant.ps1"

    $Script:DesiredState = @{
        Direction = 'Inbound'
        Action    = 'Allow'
        Enabled   = 'True'
        Protocol  = 'TCP'
        LocalPort = '3389'
    }
}

Describe 'Test-FirewallRuleCompliant' {

    Context 'Rule count validation' {

        It 'returns false when no rules exist' {

            Test-FirewallRuleCompliant -Rules @() -DesiredState $Script:DesiredState |
                Should -BeFalse
        }

        It 'returns false when multiple rules exist' {

            Test-FirewallRuleCompliant -Rules @(
                [pscustomobject]@{}
                [pscustomobject]@{}
            ) -DesiredState $Script:DesiredState |
                Should -BeFalse
        }
    }

    Context 'Rule state validation' {

        It 'returns false when rule is disabled' {

            $rule = [pscustomobject]@{
                Enabled   = 'False'
                Direction = 'Inbound'
                Action    = 'Allow'
            }

            Test-FirewallRuleCompliant -Rules @($rule) -DesiredState $Script:DesiredState |
                Should -BeFalse
        }

        It 'returns false when direction is outbound' {

            $rule = [pscustomobject]@{
                Enabled   = 'True'
                Direction = 'Outbound'
                Action    = 'Allow'
            }

            Test-FirewallRuleCompliant -Rules @($rule) -DesiredState $Script:DesiredState |
                Should -BeFalse
        }

        It 'returns false when action is block' {

            $rule = [pscustomobject]@{
                Enabled   = 'True'
                Direction = 'Inbound'
                Action    = 'Block'
            }

            Test-FirewallRuleCompliant -Rules @($rule) -DesiredState $Script:DesiredState |
                Should -BeFalse
        }
    }

    Context 'Port filter validation' {

        It 'returns false when port filter is null' {

            Mock Get-RulePortFilter { $null }

            $rule = [pscustomobject]@{
                Enabled   = 'True'
                Direction = 'Inbound'
                Action    = 'Allow'
            }

            Test-FirewallRuleCompliant -Rules @($rule) -DesiredState $Script:DesiredState |
                Should -BeFalse
        }

        It 'returns false when protocol differs' {

            Mock Get-RulePortFilter {
                [pscustomobject]@{
                    Protocol  = 'UDP'
                    LocalPort = '3389'
                }
            }

            $rule = [pscustomobject]@{
                Enabled   = 'True'
                Direction = 'Inbound'
                Action    = 'Allow'
            }

            Test-FirewallRuleCompliant -Rules @($rule) -DesiredState $Script:DesiredState |
                Should -BeFalse
        }

        It 'returns false when port differs' {

            Mock Get-RulePortFilter {
                [pscustomobject]@{
                    Protocol  = 'TCP'
                    LocalPort = '3390'
                }
            }

            $rule = [pscustomobject]@{
                Enabled   = 'True'
                Direction = 'Inbound'
                Action    = 'Allow'
            }

            Test-FirewallRuleCompliant -Rules @($rule) -DesiredState $Script:DesiredState |
                Should -BeFalse
        }

        It 'returns false when multiple ports exist' {

            Mock Get-RulePortFilter {
                [pscustomobject]@{
                    Protocol  = 'TCP'
                    LocalPort = @('3388', '3389')
                }
            }

            $rule = [pscustomobject]@{
                Enabled   = 'True'
                Direction = 'Inbound'
                Action    = 'Allow'
            }

            Test-FirewallRuleCompliant -Rules @($rule) -DesiredState $Script:DesiredState |
                Should -BeFalse
        }
    }

    Context 'Positive validation' {

        It 'returns true when rule matches desired state' {

            Mock Get-RulePortFilter {
                [pscustomobject]@{
                    Protocol  = 'TCP'
                    LocalPort = '3389'
                }
            }

            $rule = [pscustomobject]@{
                Enabled   = 'True'
                Direction = 'Inbound'
                Action    = 'Allow'
            }

            Test-FirewallRuleCompliant -Rules @($rule) -DesiredState $Script:DesiredState |
                Should -BeTrue

            Should -Invoke Get-RulePortFilter -Times 1
        }
    }
}
