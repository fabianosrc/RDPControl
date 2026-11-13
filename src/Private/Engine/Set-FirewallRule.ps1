<#
.SYNOPSIS
Ensures a managed firewall rule exists and matches the desired state
for a given TCP port.

.DESCRIPTION
Creates or updates the RDPControl-managed inbound TCP Allow firewall
rule in the PersistentStore. The rule is identified by its internal
name (RDPControl-RDP-Rule), which never changes regardless of the
display name or port requested.

On creation, -RuleName is applied as the rule DisplayName.
On update, -RuleName is applied as the new DisplayName via
-NewDisplayName. Calling the function with a different -RuleName
relabels the existing rule without creating a second one.

The function is idempotent: when the existing rule already matches
the desired state and display name, no changes are applied.

When an update is required but fails, the function attempts to restore
the previous state automatically. If restoration also fails, an
AggregateException is thrown carrying both failures.

.PARAMETER Port
TCP port number to allow inbound traffic. Must be between 1024 and 65535.

.PARAMETER RuleName
Display name for the firewall rule. Controls only the DisplayName
property; the internal Name is always RDPControl-RDP-Rule.
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
        $managedName = 'RDPControl-RDP-Rule'

        $lookupParams = @{
            Name        = $managedName
            ErrorAction = 'Stop'
        }

        $desiredState = @{
            Direction = 'Inbound'
            Action    = 'Allow'
            Enabled   = 'True'
            Protocol  = 'TCP'
            LocalPort = [string]$Port
        }

        try {
            $existingRules = @(Get-FirewallRule @lookupParams)

            if ($existingRules.Count -gt 1) {
                throw "More than one local firewall rule matched '$managedName'."
            }

            $hasRule = $existingRules.Count -eq 1

            if ($hasRule) {
                $existing = $existingRules[0]

                $compliantParams = @{
                    Rules        = $existingRules
                    DesiredState = $desiredState
                    ErrorAction  = 'Stop'
                }

                $isCompliant = Test-FirewallRuleCompliant @compliantParams

                if ($isCompliant -and $existing.DisplayName -ceq $RuleName) {
                    Write-Verbose -Message (
                        "Firewall rule '$managedName' is already compliant."
                    )

                    return
                }
            }

            if (-not $PSCmdlet.ShouldProcess($managedName,
                "Apply firewall rule for TCP port $Port")
            ) {
                return
            }

            $writeParams = @{
                Name        = $managedName
                PolicyStore = 'PersistentStore'
                Direction   = $desiredState.Direction
                Action      = $desiredState.Action
                Enabled     = $desiredState.Enabled
                Protocol    = $desiredState.Protocol
                LocalPort   = $desiredState.LocalPort
                ErrorAction = 'Stop'
                Confirm     = $false
            }

            if (-not $hasRule) {
                $newRuleParams = $writeParams.Clone()
                $newRuleParams.DisplayName = $RuleName
                $newRuleParams.Profile     = 'Any'

                New-NetFirewallRule @newRuleParams | Out-Null

                Write-Verbose -Message (
                    "Applied firewall rule '$managedName' for TCP port $Port."
                )

                return
            }

            $filters = @(Get-RulePortFilter -InputObject $existing)

            if ($filters.Count -ne 1) {
                throw "Cannot capture the current port filter for '$managedName'."
            }

            $oldProtocol = [string]$filters[0].Protocol

            if ($oldProtocol -eq '6') {
                $oldProtocol = 'TCP'
            }

            if ($oldProtocol -eq '17') {
                $oldProtocol = 'UDP'
            }

            $oldPorts = [string[]]@($filters[0].LocalPort)

            if ($oldProtocol -notin @('TCP', 'UDP') -or
                $oldPorts.Count -eq 0 -or $oldPorts -contains '')
            {
                throw (
                    "Cannot safely restore the current protocol and " +
                    "ports for '$managedName'."
                )
            }

            $restoreParams = $writeParams.Clone()
            $restoreParams.Direction      = [string]$existing.Direction
            $restoreParams.Action         = [string]$existing.Action
            $restoreParams.Enabled        = [string]$existing.Enabled
            $restoreParams.Protocol       = $oldProtocol
            $restoreParams.LocalPort      = $oldPorts
            $restoreParams.NewDisplayName = [string]$existing.DisplayName

            try {
                $updateParams = $writeParams.Clone()
                $updateParams.NewDisplayName = $RuleName

                Set-NetFirewallRule @updateParams | Out-Null

                $updatedRules = @(Get-FirewallRule @lookupParams)

                $compliantParams = @{
                    Rules        = $updatedRules
                    DesiredState = $desiredState
                    ErrorAction  = 'Stop'
                }

                $isCompliant = Test-FirewallRuleCompliant @compliantParams

                if ($updatedRules.Count -ne 1 -or -not $isCompliant -or
                    $updatedRules[0].DisplayName -cne $RuleName
                ) {
                    throw (
                        "Firewall rule '$managedName' did not match " +
                        "the requested state after update."
                    )
                }
            } catch {
                $updateFailure = $_

                try {
                    Set-NetFirewallRule @restoreParams | Out-Null
                } catch {
                    throw [System.AggregateException]::new(
                        "Firewall rule '$managedName' update and rollback both failed.",
                        [System.Exception[]]@($updateFailure.Exception, $_.Exception)
                    )
                }

                throw $updateFailure
            }

            Write-Verbose -Message (
                "Applied firewall rule '$managedName' for TCP port $Port."
            )
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'SetFirewallRuleFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $managedName
                )
            )
        }
    }
}
