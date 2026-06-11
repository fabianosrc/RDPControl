<#
.SYNOPSIS
Returns the port filter associated with a firewall rule.

.DESCRIPTION
Wraps Get-NetFirewallPortFilter to retrieve the port filter object
associated with the given firewall rule. Returns $null when no filter
is found or the rule object is invalid.

Exists as a wrapper to allow unit testing of firewall compliance logic
without requiring real CimInstance objects.

.PARAMETER InputObject
The firewall rule object returned by Get-NetFirewallRule.

.EXAMPLE
PS C:\> Get-NetFirewallRule -DisplayName 'Remote Desktop Connection' |
            Get-RulePortFilter

.INPUTS
Microsoft.Management.Infrastructure.CimInstance

.OUTPUTS
Microsoft.Management.Infrastructure.CimInstance
#>
function Get-RulePortFilter {
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )

    process {
        Get-NetFirewallPortFilter -AssociatedNetFirewallRule $InputObject -ErrorAction SilentlyContinue
    }
}
