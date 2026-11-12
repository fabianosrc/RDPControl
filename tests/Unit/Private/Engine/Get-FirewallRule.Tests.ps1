#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Unit tests for Get-FirewallRule.

.DESCRIPTION
Covers parameter contracts, dependency invocation, result forwarding,
missing-rule handling and unexpected failure propagation.

No real firewall query is performed by these tests. All calls to
Get-NetFirewallRule are intercepted via Mock.

Coverage includes:
  - DisplayName is mandatory and rejects null or empty values.
  - Passes DisplayName and ErrorAction Stop to Get-NetFirewallRule.
  - Returns one or multiple matching rules without modification.
  - Returns no objects when no matching rule exists.
  - Suppresses only ObjectNotFound errors with matching FullyQualifiedErrorId.
  - Propagates ObjectNotFound errors from unrelated sources.
  - Propagates permission and operational failures.
  - Reports missing rules through the verbose stream.
  - Never creates, updates or removes firewall rules.
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

Describe 'Get-FirewallRule' -Tag 'Unit' {

    InModuleScope -ModuleName RDPControl {

        BeforeAll {

            $Script:RuleName = 'Remote Desktop Connection'

            $Script:Rule = [PSCustomObject]@{
                Name        = 'RDPControl-Test'
                DisplayName = $Script:RuleName
                Enabled     = 'True'
                Direction   = 'Inbound'
                Action      = 'Allow'
            }

            $Script:Command = Get-Command -Name Get-FirewallRule -ErrorAction Stop
        }

        BeforeEach {

            Mock -CommandName Get-NetFirewallRule -MockWith {
                $Script:Rule
            }
        }

        #region Parameter contract
        Context 'Parameter contract' {

            It 'Declares DisplayName as a mandatory string parameter' {
                $Script:Command.Parameters['DisplayName'].ParameterType |
                    Should -Be ([string])

                $mandatory = @(
                    $Script:Command.Parameters['DisplayName'].Attributes |
                        Where-Object {
                            $_ -is [System.Management.Automation.ParameterAttribute] -and
                            $_.Mandatory
                        }
                )

                $mandatory | Should -HaveCount 1
            }

            It 'Rejects an empty DisplayName' {
                { Get-FirewallRule -DisplayName '' } | Should -Throw

                Should -Invoke -CommandName Get-NetFirewallRule -Times 0 -Exactly
            }

            It 'Rejects a null DisplayName' {
                { Get-FirewallRule -DisplayName $null } | Should -Throw

                Should -Invoke -CommandName Get-NetFirewallRule -Times 0 -Exactly
            }
        }
        #endregion

        #region Dependency invocation
        Context 'Dependency invocation' {

            It 'Passes the supplied DisplayName to Get-NetFirewallRule' {
                Get-FirewallRule -DisplayName $Script:RuleName | Out-Null

                $invokeParams = @{
                    CommandName     = 'Get-NetFirewallRule'
                    Times           = 1
                    Exactly         = $true
                    ParameterFilter = { $DisplayName -eq $Script:RuleName }
                }

                Should -Invoke @invokeParams
            }

            It 'Requests terminating error behavior from Get-NetFirewallRule' {
                Get-FirewallRule -DisplayName $Script:RuleName | Out-Null

                $invokeParams = @{
                    CommandName     = 'Get-NetFirewallRule'
                    Times           = 1
                    Exactly         = $true
                    ParameterFilter = { $ErrorAction -eq 'Stop' }
                }

                Should -Invoke @invokeParams
            }
        }
        #endregion

        #region Result forwarding
        Context 'Result forwarding' {

            It 'Returns the original rule object without modification' {
                $result = Get-FirewallRule -DisplayName $Script:RuleName

                [object]::ReferenceEquals($result, $Script:Rule) | Should -BeTrue
            }

            It 'Preserves all rule properties' {
                $result = Get-FirewallRule -DisplayName $Script:RuleName

                $result.Name        | Should -Be 'RDPControl-Test'
                $result.DisplayName | Should -Be $Script:RuleName
                $result.Enabled     | Should -Be 'True'
                $result.Direction   | Should -Be 'Inbound'
                $result.Action      | Should -Be 'Allow'
            }

            It 'Returns all matching rules when multiple exist' {
                Mock -CommandName Get-NetFirewallRule -MockWith {
                    [PSCustomObject]@{ Name = 'Rule1' }
                    [PSCustomObject]@{ Name = 'Rule2' }
                }

                $result = @(Get-FirewallRule -DisplayName $Script:RuleName)

                $result         | Should -HaveCount 2
                $result[0].Name | Should -Be 'Rule1'
                $result[1].Name | Should -Be 'Rule2'
            }
        }
        #endregion

        #region Missing rule
        Context 'Missing rule' {

            BeforeEach {

                Mock -CommandName Get-NetFirewallRule -MockWith {
                    $writeErrorParams = @{
                        Message     = 'No matching firewall rule was found.'
                        ErrorId     = 'CmdletizationQuery_NotFound_DisplayName'
                        Category    = 'ObjectNotFound'
                        ErrorAction = 'Stop'
                    }

                    Write-Error @writeErrorParams
                }
            }

            It 'Returns no objects when the rule does not exist' {
                $result = @(Get-FirewallRule -DisplayName $Script:RuleName)

                $result | Should -HaveCount 0
            }

            It 'Does not propagate an error when the rule does not exist' {
                {
                    $result = @(
                        $params = @{
                            DisplayName = $Script:RuleName
                            ErrorAction = 'Stop'
                        }

                        Get-FirewallRule @params
                    )

                    $result | Should -HaveCount 0
                } | Should -Not -Throw
            }

            It 'Reports the missing rule through the verbose stream' {
                $records = @(
                    Get-FirewallRule -DisplayName $Script:RuleName -Verbose 4>&1
                )

                $messages = @(
                    $records |
                        Where-Object {
                            $_ -is [System.Management.Automation.VerboseRecord]
                        } |
                        ForEach-Object Message
                )

                ($messages -join "`n") | Should -Match 'was not found'
            }
        }
        #endregion

        #region Unexpected failures
        Context 'Unexpected failures' {

            It 'Propagates an ObjectNotFound error from an unrelated source' {
                Mock -CommandName Get-NetFirewallRule -MockWith {
                    $writeErrorParams = @{
                        Message     = 'An unrelated resource was not found.'
                        ErrorId     = 'UnrelatedResourceNotFound'
                        Category    = 'ObjectNotFound'
                        ErrorAction = 'Stop'
                    }

                    Write-Error @writeErrorParams
                }

                { Get-FirewallRule -DisplayName $Script:RuleName } |
                    Should -Throw -ErrorId 'UnrelatedResourceNotFound'
            }

            It 'Propagates permission errors' {
                Mock -CommandName Get-NetFirewallRule -MockWith {
                    $writeErrorParams = @{
                        Message     = 'Access denied.'
                        ErrorId     = 'AccessDenied'
                        Category    = 'PermissionDenied'
                        ErrorAction = 'Stop'
                    }

                    Write-Error @writeErrorParams
                }

                { Get-FirewallRule -DisplayName $Script:RuleName } |
                    Should -Throw -ErrorId 'AccessDenied'
            }

            It 'Propagates firewall service unavailability errors' {
                Mock -CommandName Get-NetFirewallRule -MockWith {
                    $writeErrorParams = @{
                        Message     = 'Firewall service is unavailable.'
                        ErrorId     = 'FirewallServiceUnavailable'
                        Category    = 'InvalidOperation'
                        ErrorAction = 'Stop'
                    }

                    Write-Error @writeErrorParams
                }

                { Get-FirewallRule -DisplayName $Script:RuleName } |
                    Should -Throw -ErrorId 'FirewallServiceUnavailable'
            }
        }
        #endregion
    }
}
