#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-FirewallRule.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-RulePortFilter.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Test-FirewallRuleCompliant.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Set-FirewallRule.ps1"
}

Describe 'Set-FirewallRule' {

    BeforeEach {
        Mock Get-FirewallRule { }
        Mock Remove-NetFirewallRule { }
        Mock New-NetFirewallRule { }
        Mock Test-FirewallRuleCompliant { $false }
    }

    Context 'Parameter validation' {

        It 'Rejects ports below the allowed range' {
            { Set-FirewallRule -Port 1023 } | Should -Throw
        }

        It 'Rejects ports above the allowed range' {
            { Set-FirewallRule -Port 65536 } | Should -Throw
        }
    }

    Context 'Rule creation' {

        It 'Creates a new rule when no rule exists' {
            Mock Get-FirewallRule { @() }

            Set-FirewallRule -Port 3389 -Confirm:$false

            Should -Invoke Test-FirewallRuleCompliant -Times 1
            Should -Invoke New-NetFirewallRule -Times 1
            Should -Invoke Remove-NetFirewallRule -Times 0
        }
    }

    Context 'Idempotency' {

        It 'Does nothing when rule is already compliant' {
            Mock Get-FirewallRule { @('ExistingRule') }
            Mock Test-FirewallRuleCompliant { $true }

            Set-FirewallRule -Port 3389 -Confirm:$false

            Should -Invoke Test-FirewallRuleCompliant -Times 1
            Should -Invoke New-NetFirewallRule -Times 0
            Should -Invoke Remove-NetFirewallRule -Times 0
        }
    }

    Context 'ShouldProcess support' {

        It 'Does not create a rule when -WhatIf is specified' {
            Mock Get-FirewallRule { @() }

            Set-FirewallRule -Port 3389 -WhatIf

            Should -Invoke New-NetFirewallRule -Times 0
            Should -Invoke Remove-NetFirewallRule -Times 0
        }
    }

    Context 'Error handling' {

        It 'Wraps New-NetFirewallRule failures' {
            Mock Get-FirewallRule { @() }
            Mock New-NetFirewallRule { throw 'Boom' }

            { Set-FirewallRule -Port 3389 -Confirm:$false } |
                Should -Throw -ErrorId 'SetFirewallRuleFailed,*'
        }

        It 'Wraps Remove-NetFirewallRule failures' {
            Mock Get-FirewallRule { @('Rule1') }
            Mock Test-FirewallRuleCompliant { $false }
            Mock Remove-NetFirewallRule { throw 'Boom' }

            { Set-FirewallRule -Port 3389 -Confirm:$false } |
                Should -Throw -ErrorId 'SetFirewallRuleFailed,*'
        }
    }

    Context 'Verbose logging' {

        It 'Writes a verbose message when rule is already compliant' {
            Mock Get-FirewallRule { @('Rule1') }
            Mock Test-FirewallRuleCompliant { $true }

            $verbose = & {
                Set-FirewallRule -Port 3389 -Confirm:$false -Verbose
            } 4>&1

            $messages = $verbose |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
                ForEach-Object Message

            ($messages -join "`n") | Should -Match 'already compliant'
        }

        It 'Writes a verbose message when rule is applied' {
            Mock Get-FirewallRule { @() }
            Mock Test-FirewallRuleCompliant { $false }

            $verbose = & {
                Set-FirewallRule -Port 3389 -Confirm:$false -Verbose
            } 4>&1

            $messages = $verbose |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
                ForEach-Object Message

            ($messages -join "`n") | Should -Match 'Applied firewall rule'
        }
    }
}
