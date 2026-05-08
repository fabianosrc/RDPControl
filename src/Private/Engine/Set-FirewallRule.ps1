<#
.SYNOPSIS
Ensures a Windows Firewall rule exists and is consistent for a given TCP port.

.DESCRIPTION
Creates or updates an inbound TCP firewall rule with the desired configuration.
The function is idempotent: it only applies changes when the current state
differs from the desired state.

.PARAMETER Port
TCP port number to allow inbound traffic.

.PARAMETER RuleName
Display name of the firewall rule.

.EXAMPLE
PS C:\> Set-FirewallRule -Port 3389

.EXAMPLE
PS C:\> Set-FirewallRule -Port 3390 -RuleName 'Custom RDP Rule'

.INPUTS
None

.OUTPUTS
None
#>
function Set-FirewallRule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1024, 65535)]
        [int]$Port,

        [ValidateNotNullOrEmpty()]
        [string]$RuleName = 'RDPControl - Remote Desktop Connection'
    )

    process {
        # Desired state definition
        $desired = @{
            DisplayName = $RuleName
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = $Port
            Action      = 'Allow'
            Profile     = 'Domain, Private, Public'
            Enabled     = 'True'
        }

        $existingRules = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue

        if (-not $existingRules) {
            if ($PSCmdlet.ShouldProcess($RuleName, "Create firewall rule for TCP port $Port")) {
                New-NetFirewallRule @desired | Out-Null
                Write-Verbose -Message "Created firewall rule '$RuleName' for port $Port."
            }
            return
        }

        # Idempotency check
        $needsUpdate = $false

        foreach ($rule in $existingRules) {
            $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue

            if (-not $portFilter -or $portFilter.LocalPort -ne $Port) {
                $needsUpdate = $true
                break
            }
        }

        if (-not $needsUpdate) {
            Write-Verbose -Message "Firewall rule '$RuleName' already in desired state (port $Port). No changes needed."
            return
        }

        if ($PSCmdlet.ShouldProcess($RuleName, "Update firewall rule to TCP port $Port")) {
            $paramSet = @{
                DisplayName = $RuleName
                Direction   = $desired.Direction
                Protocol    = $desired.Protocol
                LocalPort   = $Port
                Action      = $desired.Action
                Profile     = $desired.Profile
                Enabled     = $desired.Enabled
            }

            Set-NetFirewallRule @paramSet | Out-Null
            Write-Verbose -Message "Updated firewall rule '$RuleName' to port $Port."
        }
    }
}
