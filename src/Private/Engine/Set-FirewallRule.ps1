<#
.SYNOPSIS
Ensures a Windows Firewall rule exists and is consistent for a given TCP port.

.DESCRIPTION
Creates or recreates an inbound TCP Allow firewall rule with the desired
configuration. The function is fully idempotent: it evaluates drift across
all matching rules before applying any change.

Drift is detected when any existing rule deviates from the desired state
in port, protocol, direction, action, or enabled status. Non-compliant
rules are removed and recreated atomically.

.PARAMETER Port
TCP port number to allow inbound traffic. Must be between 1024 and 65535.

.PARAMETER RuleName
Display name of the firewall rule.
Defaults to 'Remote Desktop Connection'.

.EXAMPLE
PS C:\> Set-FirewallRule -Port 3389

.EXAMPLE
PS C:\> Set-FirewallRule -Port 3390 -RuleName 'Custom RDP Rule'

.EXAMPLE
PS C:\> Set-FirewallRule -Port 3390 -WhatIf

.INPUTS
None

.OUTPUTS
None
#>
function Set-FirewallRule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateRange(1024, 65535)]
        [int]$Port,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RuleName = 'Remote Desktop Connection'
    )

    process {
        try {
            # ------------------------
            # Desired state definition
            # ------------------------
            $desiredState = @{
                Direction = 'Inbound'
                Action    = 'Allow'
                Enabled   = 'True'
                Protocol  = 'TCP'
                LocalPort = [string]$Port
            }

            # -------------------------
            # 1. Collect existing rules
            # -------------------------
            $existingRules = @(
                Get-FirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
            )

            # ----------------------------------------
            # 2. Evaluate compliance (drift detection)
            # ----------------------------------------
            $isCompliant = Test-FirewallRuleCompliant -Rules $existingRules -DesiredState $desiredState

            if ($isCompliant) {
                Write-Verbose -Message (
                    "Firewall rule '$RuleName' is already compliant for port $Port. No changes needed."
                )
                return
            }

            # ------------------------------
            # 3. Remediate (remove + create)
            # ------------------------------
            if (-not $PSCmdlet.ShouldProcess(
                $RuleName,
                "Apply firewall rule for TCP port $Port"
            )) {
                return
            }

            foreach ($rule in $existingRules) {
                Remove-NetFirewallRule -InputObject $rule

                Write-Verbose -Message "Removed non-compliant firewall rule '$RuleName'."
            }

            $newRuleParams = @{
                DisplayName = $RuleName
                Direction   = $desiredState.Direction
                Protocol    = $desiredState.Protocol
                LocalPort   = $Port
                Action      = $desiredState.Action
                Profile     = 'Any'
                Enabled     = $desiredState.Enabled
            }

            New-NetFirewallRule @newRuleParams | Out-Null

            Write-Verbose -Message "Applied firewall rule '$RuleName' for TCP port $Port."
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'SetFirewallRuleFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $RuleName
                )
            )
        }
    }
}
