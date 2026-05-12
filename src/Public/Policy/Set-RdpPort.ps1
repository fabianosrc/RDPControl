<#
.SYNOPSIS
Changes the RDP listening port.

.DESCRIPTION
Updates the RDP listening port in the Windows Registry, optionally updates
the firewall rule, and restarts TermService to apply the change.

.PARAMETER Port
Target port number. Must be between 1024 and 65535.

.PARAMETER SkipFirewall
Skips automatic firewall rule management.

.PARAMETER Force
Re-applies configuration even if the port is already set.

.EXAMPLE
PS C:\> Set-RdpPort -Port 3390

.EXAMPLE
PS C:\> Set-RdpPort -Port 3390 -SkipFirewall

.EXAMPLE
PS C:\> Set-RdpPort -Port 3390 -WhatIf

.INPUTS
None

.OUTPUTS
PSCustomObject
Contains:
- Port
- PreviousPort
- ConfiguredAt
#>

function Set-RdpPort {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateRange(1024, 65535)]
        [int]$Port,

        [Parameter()]
        [switch]$SkipFirewall,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new(
                        'Set-RdpPort requires elevated privileges. Run as Administrator.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }
    }

    process {
        $registryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

        $registryParams = @{
            Path  = $registryPath
            Name  = 'PortNumber'
            Strict = $true
        }

        $currentPort = [int](Get-RegistryValue @registryParams)

        if (-not $Force -and $currentPort -eq $Port) {
            Write-Warning -Message "RDP port already set to $Port. Use -Force to reapply."
            return
        }

        if (-not ($Force -or $PSCmdlet.ShouldProcess("RDP Configuration", "Change port from $currentPort to $Port"))) {
            return
        }

        try {
            $setRegParams = @{
                Path  = $registryPath
                Name  = 'PortNumber'
                Value = $Port
                Type  = 'DWord'
            }

            Set-RegistryValue @setRegParams

            if (-not $SkipFirewall) {
                Set-FirewallRule -Port $Port
            }

            Stop-TermService
            Start-TermService
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'SetRdpPortFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $Port
                )
            )
        }

        New-StoreAuditRecord -Operation 'Set-RdpPort' -Details "Port=$Port;PreviousPort=$currentPort" | Out-Null

        [PSCustomObject]@{
            Port         = $Port
            PreviousPort = $currentPort
            ConfiguredAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
