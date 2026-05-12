<#
.SYNOPSIS
Returns the current RDP service state.

.DESCRIPTION
Reads the Remote Desktop configuration from registry and service state
from TermService.

.EXAMPLE
PS C:\> Get-RdpService

.INPUTS
None

.OUTPUTS
PSCustomObject
Contains:
- Enabled
- Status
- CheckedAt
#>

function Get-RdpService {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param ()

    begin {
        Assert-RdpEnvironment
    }

    process {
        $registryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'

        $denyConnections = Get-RegistryValue -Path $registryPath -Name 'fDenyTSConnections' -Strict

        try {
            $service = Get-Service -Name 'TermService' -ErrorAction Stop
            $serviceStatus = $service.Status.ToString()
        } catch {
            $serviceStatus = 'Unknown'
        }

        $enabled = [int]$denyConnections -eq 0

        [PSCustomObject]@{
            Enabled   = $enabled
            Status    = $serviceStatus
            CheckedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
