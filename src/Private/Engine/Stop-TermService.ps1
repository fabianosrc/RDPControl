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
PS C:\> Stop-TermService -Verbose

.EXAMPLE
PS C:\> Stop-TermService -TimeoutSeconds 60

.OUTPUTS
None
#>
function Stop-TermService {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'ShouldProcess is handled by the calling public function.'
    )]
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    $serviceName = 'TermService'
    $service     = Get-Service -Name $serviceName -ErrorAction Stop

    if ($service.Status -eq 'Stopped') {
        Write-Verbose -Message "$serviceName is already stopped."
        return
    }

    Write-Verbose -Message "Stopping $serviceName (timeout: ${TimeoutSeconds}s)..."

    Stop-Service -Name $serviceName -Force -ErrorAction Stop

    try {
        $service.WaitForStatus('Stopped', [timespan]::FromSeconds($TimeoutSeconds))
    } catch [System.ServiceProcess.TimeoutException] {
        Write-Warning -Message "$serviceName did not stop within ${TimeoutSeconds}s. Forcing termination..."

        $processId = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" |
            Select-Object -ExpandProperty ProcessId

        $process = if ($processId -gt 0) {
            Get-Process -Id $processId -ErrorAction SilentlyContinue
        }

        if ($null -ne $process) {
            $process.Kill()
            $process.WaitForExit(5000)
        }

        $service.Refresh()

        if ($service.Status -ne 'Stopped') {
            throw "Failed to stop $serviceName even after forced termination."
        }

        Write-Verbose -Message "$serviceName forcefully terminated."
    }
}
