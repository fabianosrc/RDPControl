<#
.SYNOPSIS
Stops the RDPControl self-healing watchdog.

.DESCRIPTION
Unregisters the Windows Scheduled Task created by Start-RdpWatchdog.

.PARAMETER Force
Bypasses the confirmation prompt.

.EXAMPLE
PS C:\> Stop-RdpWatchdog

.EXAMPLE
PS C:\> Stop-RdpWatchdog -Force

.INPUTS
None

.OUTPUTS
PSCustomObject with properties:
    Status    [string] - 'Stopped'
    StoppedAt [string] - ISO 8601 UTC timestamp
#>
function Stop-RdpWatchdog {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [switch]$Force
    )

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.UnauthorizedAccessException]::new(
                    'Stop-RdpWatchdog requires elevated privileges. ' +
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
        $taskName = 'RDPControl Watchdog'
        $taskPath = '\RDPControl\'

        $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

        if ($null -eq $task) {
            Write-Warning -Message 'RDPControl Watchdog is not registered. Nothing to stop.'
            return
        }

        if (-not ($Force -or $PSCmdlet.ShouldProcess('RDPControl Watchdog', 'Unregister Scheduled Task'))) {
            return
        }

        try {
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false

            New-StoreAuditRecord -Operation 'Stop-RdpWatchdog' -Details 'Status=Stopped' | Out-Null

            Write-Verbose -Message 'RDPControl Watchdog scheduled task unregistered.'

            [PSCustomObject]@{
                Status    = 'Stopped'
                StoppedAt = (Get-Date).ToUniversalTime().ToString('o')
            }
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'StopWatchdogFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $taskName
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
