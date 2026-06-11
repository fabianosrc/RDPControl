<#
.SYNOPSIS
Evaluates whether a collection of firewall rules matches the desired state.

.DESCRIPTION
Returns $true only when the collection contains exactly one rule and all
tracked attributes match the desired state: Enabled, Direction, Action,
Protocol, and LocalPort.

Port filter data is retrieved via Get-RulePortFilter, which can be mocked
in unit tests without requiring real CimInstance objects.

Profile is intentionally excluded from compliance evaluation because
the NetSecurity module returns inconsistent string representations
across Windows builds (e.g. 'Any' vs 'Domain, Private, Public').

.PARAMETER Rules
Array of firewall rule objects returned by Get-FirewallRules.
An empty collection is considered non-compliant.

.PARAMETER DesiredState
Hashtable defining the expected values for Direction, Action, Enabled,
Protocol, and LocalPort.

.EXAMPLE
PS C:\> $rules = Get-FirewallRules -DisplayName 'Remote Desktop Connection'
PS C:\> $desired = @{
            Direction = 'Inbound'
            Action    = 'Allow'
            Enabled   = 'True'
            Protocol  = 'TCP'
            LocalPort = '3389'
        }
PS C:\> Test-FirewallRuleCompliant -Rules $rules -DesiredState $desired

.INPUTS
None

.OUTPUTS
System.Boolean
#>
function Test-FirewallRuleCompliant {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules,

        [Parameter(Mandatory)]
        [hashtable]$DesiredState
    )

    # Must have exactly one rule
    if ($Rules.Count -ne 1) {
        return $false
    }

    $rule = $Rules[0]

    # Normalize rule attributes
    $ruleEnabled   = [string]$rule.Enabled
    $ruleDirection = [string]$rule.Direction
    $ruleAction    = [string]$rule.Action

    if ($ruleEnabled -ne [string]$DesiredState.Enabled) {
        return $false
    }

    if ($ruleDirection -ne [string]$DesiredState.Direction) {
        return $false
    }

    if ($ruleAction -ne [string]$DesiredState.Action) {
        return $false
    }

    # Port filter - retrieved via wrapper to allow mocking
    $portFilter = Get-RulePortFilter -InputObject $rule

    if (-not $portFilter) {
        return $false
    }

    if ([string]$portFilter.Protocol -ne [string]$DesiredState.Protocol) {
        return $false
    }

    $ports = @($portFilter.LocalPort | ForEach-Object { [string]$_ })

    if ($ports.Count -ne 1) {
        return $false
    }

    if ($ports[0] -ne [string]$DesiredState.LocalPort) {
        return $false
    }

    return $true
}
