<#
.SYNOPSIS
Enables or disables Remote Desktop access.

.DESCRIPTION
Controls Remote Desktop access using the preferred CIM-based configuration
method with automatic fallback to registry-based configuration.

The CIM method uses the Win32_TerminalServiceSetting class from the
root/cimv2/TerminalServices namespace, which properly synchronizes:
    - Windows Settings UI toggle
    - Firewall configuration
    - Remote Desktop operational state

If the CIM method is unavailable or fails for any reason, the command
automatically falls back to registry-based configuration to ensure
compatibility across all supported Windows environments.

When disabling Remote Desktop, the command detects whether the current
session is an active Remote Desktop session and requires explicit
confirmation to prevent accidental lock-out.

.PARAMETER Enabled
Enables Remote Desktop access.

.PARAMETER Disabled
Disables Remote Desktop access.

.PARAMETER Force
Suppresses the standard confirmation prompt.
Does not suppress the lock-out protection confirmation when disabling
from an active Remote Desktop session.

.EXAMPLE
PS C:\> Set-RdpService -Enabled

.EXAMPLE
PS C:\> Set-RdpService -Disabled

.EXAMPLE
PS C:\> Set-RdpService -Disabled -Force

.EXAMPLE
PS C:\> Set-RdpService -Enabled -WhatIf

.INPUTS
None

.OUTPUTS
PSCustomObject

Contains:
    State        [string] - 'Enabled' or 'Disabled'
    Method       [string] - 'CIM' or 'RegistryFallback'
    ConfiguredAt [string] - ISO 8601 UTC timestamp
#>
function Set-RdpService {
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
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new(
                        'Set-RdpService requires elevated privileges. ' +
                        'Run PowerShell as Administrator.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }
    }

    process {
        $stateResult = $null

        if ($Enabled) {
            if (-not ($Force -or $PSCmdlet.ShouldProcess('Remote Desktop service', 'Enable'))) {
                return
            }

            $stateResult = Set-RdpAccessState -AllowConnections $true

            Start-TermService

            New-StoreAuditRecord -Operation 'Set-RdpService' -Details "State=Enabled;Method=$($stateResult.Method)" | Out-Null

            Write-Verbose -Message "Remote Desktop enabled via method: $($stateResult.Method)"
        } elseif ($Disabled) {
            # Lock-out protection - not overridable with -Force
            if (Test-IsRdpSession) {
                Write-Warning -Message (
                    'You are currently connected via Remote Desktop. ' +
                    'Disabling the service may lock you out of this session.'
                )

                if (-not $PSCmdlet.ShouldProcess('Remote Desktop service', 'Disable (active RDP session detected)')) {
                    return
                }
            }

            # Standard confirmation - overridable with -Force
            if (-not ($Force -or $PSCmdlet.ShouldProcess('Remote Desktop service', 'Disable'))) {
                return
            }

            Stop-TermService

            $stateResult = Set-RdpAccessState -AllowConnections $false

            New-StoreAuditRecord -Operation 'Set-RdpService' -Details "State=Disabled;Method=$($stateResult.Method)" | Out-Null

            Write-Verbose -Message "Remote Desktop disabled via method: $($stateResult.Method)"
        }

        [PSCustomObject]@{
            State        = $PSCmdlet.ParameterSetName
            Method       = $stateResult.Method
            ConfiguredAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
