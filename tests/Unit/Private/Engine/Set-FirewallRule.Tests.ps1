
#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Unit tests for Set-FirewallRule.

.DESCRIPTION
Verifies the Set-FirewallRule contract using Pester mocks.

No real firewall changes are performed.

Coverage includes:
  - Parameter validation and boundaries.
  - Rule lookup and error handling.
  - Idempotency for compliant rules.
  - Rule creation when no match exists.
  - Creation parameters and custom rule names.
  - Replacement of non-compliant rules.
  - Removal of the original rule object.
  - Removal-before-creation ordering.
  - WhatIf behavior.
  - Lookup failure safety.
  - Creation and removal failure handling.
  - Absence of unintended operations.
  - Verbose diagnostic messages.

.NOTES
Remove-NetFirewallRule requires a strongly typed CIM object for
InputObject. Its mock uses RemoveParameterType so unit tests can
supply synthetic rule objects without accessing the real firewall.
#>

# InModuleScope needs to resolve the PipeDFe module during the Discovery phase,
# because that's when Context/It are executed to register the test tree. If the
# module isn't loaded at that point, InModuleScope fails before any BeforeAll or
# BeforeEach ever runs.
BeforeDiscovery {
    $moduleRoot = (Get-Item -LiteralPath $PSScriptRoot).Parent.Parent.Parent.Parent.FullName

    $moduleManifest = Join-Path -Path $moduleRoot -ChildPath 'RDPControl.psd1'

    Import-Module -Name $moduleManifest -Force -Global -ErrorAction Stop
}

Describe 'Set-FirewallRule' -Tag 'Unit' {

    InModuleScope -ModuleName RDPControl {

        BeforeAll {

            $Script:RuleName = 'Remote Desktop Connection'
            $Script:DefaultPort = 3389

            $Script:ExistingRule = [PSCustomObject]@{
                Name        = 'RDPControl-ExistingRule'
                DisplayName = 'Remote Desktop Connection'
                Enabled     = 'False'
                Direction   = 'Inbound'
                Action      = 'Allow'
            }
        }

        BeforeEach {

            $Script:OperationOrder = [System.Collections.Generic.List[string]]::new()

            Mock -CommandName Get-FirewallRule -MockWith {
                @()
            }

            Mock -CommandName Test-FirewallRuleCompliant -MockWith {
                $false
            }

            Mock -CommandName New-NetFirewallRule -MockWith {
                [void]$Script:OperationOrder.Add('New')
            }

            $mockParams = @{
                CommandName         = 'Remove-NetFirewallRule'
                RemoveParameterType = 'InputObject'
                MockWith            = {
                    [void]$Script:OperationOrder.Add('Remove')
                }
            }

            Mock @mockParams
        }

        #region Parameter validation
        Context 'Parameter validation' {

            It 'Rejects a port below the minimum allowed value' {
                { Set-FirewallRule -Port 1023 } | Should -Throw

                Should -Invoke Get-FirewallRule       -Times 0 -Exactly
                Should -Invoke New-NetFirewallRule    -Times 0 -Exactly
                Should -Invoke Remove-NetFirewallRule -Times 0 -Exactly
            }

            It 'Rejects a port above the maximum allowed value' {
                { Set-FirewallRule -Port 65536 } | Should -Throw

                Should -Invoke Get-FirewallRule       -Times 0 -Exactly
                Should -Invoke New-NetFirewallRule    -Times 0 -Exactly
                Should -Invoke Remove-NetFirewallRule -Times 0 -Exactly
            }

            It 'Accepts the minimum allowed port' {
                { Set-FirewallRule -Port 1024 -Confirm:$false } |
                    Should -Not -Throw

                Should -Invoke New-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
                    $LocalPort -eq 1024
                }
            }

            It 'Accepts the maximum allowed port' {
                { Set-FirewallRule -Port 65535 -Confirm:$false } | Should -Not -Throw

                Should -Invoke New-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
                    $LocalPort -eq 65535
                }
            }

            It 'Rejects an empty RuleName' {
                { Set-FirewallRule -Port 3389 -RuleName '' } | Should -Throw

                Should -Invoke Get-FirewallRule -Times 0 -Exactly
            }
        }
        #endregion

        #region Rule lookup
        Context 'Rule lookup' {

            It 'Uses the default firewall rule name' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke Get-FirewallRule -Times 1 -Exactly -ParameterFilter {
                    $DisplayName -eq 'Remote Desktop Connection'
                }
            }

            It 'Supports a custom firewall rule name' {
                $ruleParams = @{
                    Port     = $Script:DefaultPort
                    RuleName = 'RDPControl Custom Rule'
                    Confirm  = $false
                }

                Set-FirewallRule @ruleParams

                Should -Invoke Get-FirewallRule -Times 1 -Exactly -ParameterFilter {
                    $DisplayName -eq 'RDPControl Custom Rule'
                }

                Should -Invoke New-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
                    $DisplayName -eq 'RDPControl Custom Rule'
                }
            }

            It 'Requests terminating error behavior during lookup' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke Get-FirewallRule -Times 1 -Exactly -ParameterFilter {
                    $ErrorAction -eq 'Stop'
                }
            }

            It 'Evaluates the returned rule collection once' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke Test-FirewallRuleCompliant -Times 1 -Exactly
            }
        }
        #endregion

        #region Idempotency
        Context 'Idempotency' {

            BeforeEach {

                Mock -CommandName Get-FirewallRule -MockWith {
                    $Script:ExistingRule
                }

                Mock -CommandName Test-FirewallRuleCompliant -MockWith {
                    $true
                }
            }

            It 'Does not create a rule when the existing rule is compliant' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke New-NetFirewallRule -Times 0 -Exactly
            }

            It 'Does not remove a compliant rule' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke Remove-NetFirewallRule -Times 0 -Exactly
            }

            It 'Evaluates compliance exactly once' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke Test-FirewallRuleCompliant -Times 1 -Exactly
            }

            It 'Performs no firewall mutations when the rule is compliant' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                $Script:OperationOrder | Should -HaveCount 0
            }

            It 'Returns no output when the rule is compliant' {
                $result = @(
                    Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false
                )

                $result | Should -HaveCount 0
            }
        }
        #endregion

        #region Rule creation
        Context 'Rule creation' {

            It 'Creates exactly one rule when no matching rule exists' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke New-NetFirewallRule -Times 1 -Exactly
            }

            It 'Does not remove a rule when no matching rule exists' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke Remove-NetFirewallRule -Times 0 -Exactly
            }

            It 'Creates an inbound TCP allow rule with the correct parameters' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke New-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
                    $DisplayName -eq 'Remote Desktop Connection' -and
                    $Direction   -eq 'Inbound' -and $Protocol -eq 'TCP'   -and
                    $LocalPort   -eq 3389      -and $Action   -eq 'Allow' -and
                    $Enabled     -eq 'True'    -and $Profile  -eq 'Any'
                }
            }

            It 'Creates only the requested rule' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                $Script:OperationOrder | Should -Be @('New')
            }

            It 'Returns no output after successful creation' {
                $result = @(
                    Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false
                )

                $result | Should -HaveCount 0
            }
        }
        #endregion

        #region Rule replacement
        Context 'Rule replacement' {

            BeforeEach {

                Mock -CommandName Get-FirewallRule -MockWith {
                    $Script:ExistingRule
                }

                Mock -CommandName Test-FirewallRuleCompliant -MockWith {
                    $false
                }
            }

            It 'Removes exactly one non-compliant rule' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke Remove-NetFirewallRule -Times 1 -Exactly
            }

            It 'Creates exactly one replacement rule' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke New-NetFirewallRule -Times 1 -Exactly
            }

            It 'Passes the original rule object to removal' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke Remove-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
                    [object]::ReferenceEquals(
                        $InputObject,
                        $Script:ExistingRule
                    )
                }
            }

            It 'Removes the existing rule before creating the replacement' {
                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                $Script:OperationOrder | Should -Be @('Remove', 'New')
            }

            It 'Creates the replacement using the requested port' {
                Set-FirewallRule -Port 3390 -Confirm:$false

                $invokeParams = @{
                    CommandName     = 'New-NetFirewallRule'
                    Times           = 1
                    Exactly         = $true
                    ParameterFilter = {
                        $LocalPort -eq 3390  -and $Direction -eq 'Inbound' -and
                        $Protocol  -eq 'TCP' -and $Action     -eq 'Allow'
                    }
                }

                Should -Invoke @invokeParams
            }

            It 'Removes all matching rules when multiple non-compliant rules exist' {
                $secondRule = [PSCustomObject]@{
                    Name        = 'RDPControl-SecondRule'
                    DisplayName = 'Remote Desktop Connection'
                    Enabled     = 'False'
                    Direction   = 'Inbound'
                    Action      = 'Allow'
                }

                Mock -CommandName Get-FirewallRule -MockWith {
                    $Script:ExistingRule
                    $secondRule
                }

                Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false

                Should -Invoke Remove-NetFirewallRule -Times 2 -Exactly
                Should -Invoke New-NetFirewallRule    -Times 1 -Exactly

                $Script:OperationOrder | Should -Be @('Remove', 'Remove', 'New')
            }
        }
        #endregion

        #region WhatIf support
        Context 'WhatIf support' {

            It 'Does not create a rule under WhatIf' {
                Set-FirewallRule -Port $Script:DefaultPort -WhatIf

                Should -Invoke New-NetFirewallRule -Times 0 -Exactly
            }

            It 'Does not remove a rule under WhatIf' {
                Mock -CommandName Get-FirewallRule -MockWith {
                    $Script:ExistingRule
                }

                Set-FirewallRule -Port $Script:DefaultPort -WhatIf

                Should -Invoke Remove-NetFirewallRule -Times 0 -Exactly
            }

            It 'Does not perform any mutation under WhatIf' {
                Set-FirewallRule -Port $Script:DefaultPort -WhatIf

                $Script:OperationOrder | Should -HaveCount 0
            }

            It 'Does not modify non-compliant rules under WhatIf' {
                Mock -CommandName Get-FirewallRule -MockWith {
                    $Script:ExistingRule
                }

                Set-FirewallRule -Port $Script:DefaultPort -WhatIf

                $Script:OperationOrder | Should -HaveCount 0
            }
        }
        #endregion

        #region Lookup failure safety
        Context 'Lookup failure safety' {

            BeforeEach {

                Mock -CommandName Get-FirewallRule -MockWith {
                    throw [System.UnauthorizedAccessException]::new(
                        'Firewall query denied.'
                    )
                }
            }

            It 'Wraps lookup authorization failures with SetFirewallRuleFailed' {
                { Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false } |
                    Should -Throw -ErrorId 'SetFirewallRuleFailed,*'
            }

            It 'Does not create rules when lookup fails' {
                { Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false } |
                    Should -Throw

                Should -Invoke New-NetFirewallRule -Times 0 -Exactly
            }

            It 'Does not remove rules when lookup fails' {
                { Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false } |
                    Should -Throw

                Should -Invoke Remove-NetFirewallRule -Times 0 -Exactly
            }

            It 'Does not evaluate compliance when lookup fails' {
                { Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false } |
                    Should -Throw

                Should -Invoke Test-FirewallRuleCompliant -Times 0 -Exactly
            }

            It 'Performs no firewall mutations when lookup fails' {
                { Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false } |
                    Should -Throw

                $Script:OperationOrder | Should -HaveCount 0
            }

            It 'Propagates an operational failure as SetFirewallRuleFailed' {
                Mock -CommandName Get-FirewallRule -MockWith {
                    throw [System.InvalidOperationException]::new(
                        'Firewall service unavailable.'
                    )
                }

                { Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false } |
                    Should -Throw -ErrorId 'SetFirewallRuleFailed,*'
            }
        }
        #endregion

        #region Error wrapping
        Context 'Error wrapping' {

            It 'Wraps rule creation failures with SetFirewallRuleFailed' {
                Mock -CommandName New-NetFirewallRule -MockWith {
                    throw 'Creation failed.'
                }

                { Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false } |
                    Should -Throw -ErrorId 'SetFirewallRuleFailed,*'
            }

            It 'Does not attempt removal when initial creation fails' {
                Mock -CommandName New-NetFirewallRule -MockWith {
                    throw 'Creation failed.'
                }

                { Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false } |
                    Should -Throw

                Should -Invoke Remove-NetFirewallRule -Times 0 -Exactly
            }

            It 'Wraps rule removal failures with SetFirewallRuleFailed' {
                Mock -CommandName Get-FirewallRule -MockWith {
                    $Script:ExistingRule
                }

                $mockParams = @{
                    CommandName         = 'Remove-NetFirewallRule'
                    RemoveParameterType = 'InputObject'
                    MockWith            = { throw 'Removal failed.' }
                }

                Mock @mockParams

                { Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false } |
                    Should -Throw -ErrorId 'SetFirewallRuleFailed,*'
            }

            It 'Does not create a replacement when removal fails' {
                Mock -CommandName Get-FirewallRule -MockWith {
                    $Script:ExistingRule
                }

                $mockParams = @{
                    CommandName         = 'Remove-NetFirewallRule'
                    RemoveParameterType = 'InputObject'
                    MockWith            = { throw 'Removal failed.' }
                }

                Mock @mockParams

                { Set-FirewallRule -Port $Script:DefaultPort -Confirm:$false } |
                    Should -Throw

                Should -Invoke New-NetFirewallRule -Times 0 -Exactly
            }
        }
        #endregion

        #region Verbose logging
        Context 'Verbose logging' {

            It 'Writes a verbose message when the rule is compliant' {
                Mock -CommandName Get-FirewallRule -MockWith {
                    $Script:ExistingRule
                }

                Mock -CommandName Test-FirewallRuleCompliant -MockWith {
                    $true
                }

                $ruleParams = @{
                    Port    = $Script:DefaultPort
                    Confirm = $false
                    Verbose = $true
                }

                $messages = @(
                    & { Set-FirewallRule @ruleParams } 4>&1 |
                        Where-Object {
                            $_ -is [System.Management.Automation.VerboseRecord]
                        } |

                        ForEach-Object Message
                )

                ($messages -join "`n") | Should -Match 'already compliant'
            }

            It 'Writes a verbose message when a new rule is applied' {
                $ruleParams = @{
                    Port    = $Script:DefaultPort
                    Confirm = $false
                    Verbose = $true
                }

                $messages = @(
                    & { Set-FirewallRule @ruleParams } 4>&1 |
                        Where-Object {
                            $_ -is [System.Management.Automation.VerboseRecord]
                        } |

                        ForEach-Object Message
                )

                ($messages -join "`n") | Should -Match 'Applied firewall rule'
            }

            It 'Writes a verbose message when replacing a non-compliant rule' {
                Mock -CommandName Get-FirewallRule -MockWith {
                    $Script:ExistingRule
                }

                $ruleParams = @{
                    Port    = $Script:DefaultPort
                    Confirm = $false
                    Verbose = $true
                }

                $messages = @(
                    & { Set-FirewallRule @ruleParams } 4>&1 |
                        Where-Object {
                            $_ -is [System.Management.Automation.VerboseRecord]
                        } |
                        ForEach-Object Message
                )

                ($messages -join "`n") | Should -Match 'Removed non-compliant firewall rule'
            }
        }
        #endregion
    }
}
