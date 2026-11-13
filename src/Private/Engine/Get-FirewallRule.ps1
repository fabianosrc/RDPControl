<#
.SYNOPSIS
Retrieves firewall rules by display name or internal name.

.DESCRIPTION
Wraps Get-NetFirewallRule to retrieve firewall rules matching either
a display name or an internal name.

Exists as a wrapper to isolate NetSecurity dependencies from business
logic and allow unit testing without a live firewall.

Returns no objects when no matching rule exists. Errors unrelated to a
missing rule are propagated to the caller.

.PARAMETER DisplayName
Display name of the firewall rule to retrieve.

.PARAMETER Name
Internal name of the firewall rule to retrieve.

.EXAMPLE
PS C:\> Get-FirewallRule -DisplayName 'Remote Desktop Connection'

.EXAMPLE
PS C:\> Get-FirewallRule -Name 'RDPControl-RDP-Rule'

.INPUTS
None

.OUTPUTS
Microsoft.Management.Infrastructure.CimInstance
#>
function Get-FirewallRule {
    [CmdletBinding(DefaultParameterSetName = 'ByDisplayName')]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ByDisplayName')]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    process {
        $byName = $PSCmdlet.ParameterSetName -eq 'ByName'

        $lookupParams = @{ ErrorAction = 'Stop' }

        if ($byName) {
            $lookupParams.Name        = $Name
            $lookupParams.PolicyStore = 'PersistentStore'
            $lookupValue              = $Name
            $missingId                = 'CmdletizationQuery_NotFound_InstanceID'
        } else {
            $lookupParams.DisplayName = $DisplayName
            $lookupValue              = $DisplayName
            $missingId                = 'CmdletizationQuery_NotFound_DisplayName'
        }

        try {
            Get-NetFirewallRule @lookupParams
        } catch {
            $isNotFound = (
                $_.CategoryInfo.Category -eq
                [System.Management.Automation.ErrorCategory]::ObjectNotFound
            )

            $errorId = ($_.FullyQualifiedErrorId -split ',', 2)[0]

            if ($isNotFound -and $errorId -eq $missingId) {
                Write-Verbose -Message "Firewall rule '$lookupValue' was not found."

                return
            }

            throw
        }
    }
}
