<#
.SYNOPSIS
Enables or disables multiple simultaneous remote desktop sessions.

.DESCRIPTION
Applies or reverts the multi-session connection policy by configuring the
target system binary. A snapshot is automatically saved before any changes
are applied. Enforcement is aborted if the snapshot operation fails.

When enabling:
    - Saves a pre-enforcement snapshot (mandatory)
    - Applies binary configuration
    - Validates the result via dual verification
    - Records the operation in the audit log

When disabling:
    - Locates the most recent pre-enforcement snapshot
    - Restores the original binary
    - Validates the restore via hash comparison
    - Records the operation in the audit log

.PARAMETER Enabled
Applies the multi-session configuration.

.PARAMETER Disabled
Reverts the multi-session configuration to its original state.

.PARAMETER Force
Skips enforcement state detection and confirmation prompt.

.EXAMPLE
PS C:\> Set-RdpSessionMode -Enabled

.EXAMPLE
PS C:\> Set-RdpSessionMode -Disabled

.EXAMPLE
PS C:\> Set-RdpSessionMode -Enabled -Force

.EXAMPLE
PS C:\> Set-RdpSessionMode -Enabled -WhatIf

.INPUTS
None

.OUTPUTS
PSCustomObject
#>
function Set-RdpSessionMode {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Enabled')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Enabled')]
        [switch]$Enabled,

        [Parameter(Mandatory, ParameterSetName = 'Disabled')]
        [switch]$Disabled,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.UnauthorizedAccessException]::new(
                    'Set-RdpSessionMode requires elevated privileges. ' +
                    'Run PowerShell as Administrator.'
                ),
                'ElevationRequired',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }

    process {
        if ($Enabled) {
            if (-not $Force -and (Test-EnforcementState)) {
                Write-Warning -Message 'Multi-session is already configured. Use -Force to re-apply.'
                return
            }

            if (-not $PSCmdlet.ShouldProcess('Multi-session policy', 'Enable')) {
                return
            }

            $result = Invoke-Enforcement

            [PSCustomObject]@{
                State       = 'Enabled'
                SnapshotId  = $result.SnapshotId
                WriteOffset = $result.WriteOffset
                Hash        = $result.Hash
                EnforcedAt  = $result.EnforcedAt
            }
        } elseif ($Disabled) {
            if (-not $Force -and -not (Test-EnforcementState)) {
                Write-Warning -Message 'Multi-session is not currently configured. Nothing to revert.'
                return
            }

            if (-not ($Force -or $PSCmdlet.ShouldProcess('Multi-session policy', 'Enable'))) {
                return
            }

            $result = Undo-Enforcement

            [PSCustomObject]@{
                State      = 'Disabled'
                SnapshotId = $result.SnapshotId
                Hash       = $result.Hash
                RestoredAt = $result.RestoredAt
            }
        }
    }
}
