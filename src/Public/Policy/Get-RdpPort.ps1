<#
.SYNOPSIS
Returns the current RDP listening port.

.DESCRIPTION
Reads the RDP port number from the Windows Registry.

.EXAMPLE
PS C:\> Get-RdpPort

.INPUTS
None

.OUTPUTS
PSCustomObject
Contains:
- Port
- CheckedAt
#>

function Get-RdpPort {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param ()

    begin {
        Assert-RdpEnvironment
    }

    process {
        $registryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

        try {
            $portValue = Get-RegistryValue -Path $registryPath -Name 'PortNumber' -Strict
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'RdpPortReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $registryPath
                )
            )
        }

        if ($null -eq $portValue) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new('RDP port value not found in registry.'),
                    'RdpPortNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $registryPath
                )
            )
        }

        [PSCustomObject]@{
            Port      = [int]$portValue
            CheckedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
