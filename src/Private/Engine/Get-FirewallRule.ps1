<#
.SYNOPSIS
Retrieves firewall rules matching a display name.

.DESCRIPTION
Wraps Get-NetFirewallRule to retrieve all firewall rules matching the
specified display name.

Exists as a wrapper to isolate NetSecurity dependencies from business
logic and allow unit testing without a live firewall.

Returns no objects when no matching rule exists. Errors unrelated to a
missing rule are propagated to the caller.

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
        try {
            Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction Stop
        } catch {
            $isNotFound = (
                $_.CategoryInfo.Category -eq
                [System.Management.Automation.ErrorCategory]::ObjectNotFound
            )

            $isDisplayNameLookup = (
                $_.FullyQualifiedErrorId -like
                'CmdletizationQuery_NotFound_DisplayName*'
            )

            if ($isNotFound -and $isDisplayNameLookup) {
                Write-Verbose -Message (
                    "Firewall rule '$DisplayName' was not found."
                )

                return
            }

            throw
        }
    }
}
