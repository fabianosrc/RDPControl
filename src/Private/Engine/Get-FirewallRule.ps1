<#
.SYNOPSIS
Retrieves firewall rules matching a display name.

.DESCRIPTION
Wraps Get-NetFirewallRule to retrieve all firewall rules matching the
specified display name.

Exists as a wrapper to isolate NetSecurity dependencies from business
logic and allow unit testing without a live firewall.

.PARAMETER DisplayName
Display name of the firewall rule to retrieve.

.EXAMPLE
PS C:\> Get-FirewallRule -DisplayName 'Remote Desktop Connection'

.INPUTS
None

.OUTPUTS
Microsoft.Management.Infrastructure.CimInstance
#>
function Get-FirewallRule {
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName
    )

    process {
        Get-NetFirewallRule -DisplayName $DisplayName
    }
}
