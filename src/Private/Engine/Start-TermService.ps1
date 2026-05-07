<#
.SYNOPSIS
Starts the Remote Desktop Services (TermService) and confirms running state.

.DESCRIPTION
Starts the TermService service and waits until it reaches the 'Running' state.
Throws if the service does not reach 'Running' within the specified timeout.

.PARAMETER TimeoutSeconds
Maximum time in seconds to wait for the service to start. Defaults to 30.

.EXAMPLE
PS C:\>Start-TermService -Verbose

.EXAMPLE
PS C:\> Start-TermService -TimeoutSeconds 60

.OUTPUTS
None
#>
function Start-TermService {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    $serviceName = 'TermService'
    $service = Get-Service -Name $serviceName -ErrorAction Stop

    if ($service.Status -eq 'Running') {
        Write-Verbose -Message "$serviceName is already running."
        return
    }

    Write-Verbose -Message "Starting $serviceName (timeout: ${TimeoutSeconds}s)..."

    Start-Service -Name $serviceName -ErrorAction Stop

    $service.WaitForStatus(
        'Running',
        [TimeSpan]::FromSeconds($TimeoutSeconds)
    )

    Write-Verbose -Message "$serviceName started successfully."
}
