<#
.SYNOPSIS
Enables or disables the Remote Desktop service.

.DESCRIPTION
Controls the Remote Desktop configuration through the Windows Registry
and the TermService service.

When disabling, detects whether the current session is an active
Remote Desktop session and requires explicit confirmation to avoid
accidental lock-out.

.PARAMETER Enabled
Enables Remote Desktop access.

.PARAMETER Disabled
Disables Remote Desktop access.

.PARAMETER Force
Bypasses the standard confirmation prompt.
Does not bypass lock-out protection confirmation.

.EXAMPLE
PS C:\> Set-RdpService -Enabled

.EXAMPLE
PS C:\> Set-RdpService -Disabled

.EXAMPLE
PS C:\> Set-RdpService -Disabled -Force

.EXAMPLE
PS C:\> Set-RdpService -Disabled -WhatIf

.INPUTS
None

.OUTPUTS
PSCustomObject

Contains:
- State
- ConfiguredAt
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
                        'Set-RdpService requires elevated privileges. Run PowerShell as Administrator.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }
    }

    process {
        $registryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'

        $targetState = if ($Enabled) {
            'Enabled'
        } else {
            'Disabled'
        }

        if ($Disabled -and (Test-IsRdpSession)) {

            Write-Warning (
                'You are currently connected through Remote Desktop. ' +
                'Disabling the service may disconnect and lock you out.'
            )

            if ($PSCmdlet.ShouldProcess('Remote Desktop service', 'Disable (active RDP session detected)')) {
                return
            }
        }

        if (-not $Force) {
            if ($PSCmdlet.ShouldProcess('Remote Desktop service', $targetState)) {
                return
            }
        }

        try {
            $registryParams = @{
                Path  = $registryPath
                Name  = 'fDenyTSConnections'
                Type  = 'DWord'
                Value = if ($Enabled) { 0 } else { 1 }
            }

            Set-RegistryValue @registryParams

            if ($Enabled) {
                Set-FirewallRule -Port (Get-RdpPort).Port

                Start-TermService

                Write-Verbose -Message 'Remote Desktop service enabled.'
            } else {
                Stop-TermService

                Write-Verbose -Message 'Remote Desktop service disabled.'
            }

            New-StoreAuditRecord -Operation 'Set-RdpService' -Details "State=$targetState" | Out-Null
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'SetRdpServiceFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $targetState
                )
            )
        }

        [PSCustomObject]@{
            State        = $targetState
            ConfiguredAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
