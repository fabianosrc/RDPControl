<#
.SYNOPSIS
Stops the Remote Desktop Services (TermService) and waits for complete shutdown.

.DESCRIPTION
Stops the TermService service with a configurable timeout. Dependent services
are stopped automatically via -Force. Throws if the service does not reach
the 'Stopped' state within the specified timeout.

.PARAMETER TimeoutSeconds
Maximum time in seconds to wait for the service to stop. Defaults to 30.

.EXAMPLE
PS C:\>Stop-TerminalService -Verbose

.EXAMPLE
PS C:\> Stop-TerminalService -TimeoutSeconds 60

.OUTPUTS
None
#>
function Stop-TermService {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    $serviceName = 'TermService'
    $service = Get-Service -Name $serviceName -ErrorAction Stop

    if ($service.Status -eq 'Stopped') {
        Write-Verbose -Message "$serviceName is already stopped."
        return
    }

    Write-Verbose -Message "Stopping $serviceName (timeout: ${TimeoutSeconds}s)..."

    Stop-Service -Name $serviceName -Force -ErrorAction Stop

    $service.WaitForStatus(
        'Stopped',
        [TimeSpan]::FromSeconds($TimeoutSeconds)
    )

    Write-Verbose -Message "$serviceName stopped successfully."
}
