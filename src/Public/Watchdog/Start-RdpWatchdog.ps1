<#
.SYNOPSIS
Starts the RDPControl self-healing watchdog.

.DESCRIPTION
Registers a Windows Scheduled Task that monitors system integrity and
automatically re-applies enforcement when changes are detected.

The task is triggered at system startup (30 seconds after boot) and runs
under the SYSTEM account. Booting is used as the trigger because every
change that reverts enforcement — Windows Update servicing in particular —
ends in a restart.

This cmdlet requires an active enforcement state and will fail if no
enforced snapshot is available.

.PARAMETER Force
Bypasses confirmation prompts when registering the scheduled task.

.EXAMPLE
PS C:\> Start-RdpWatchdog

.EXAMPLE
PS C:\> Start-RdpWatchdog -Force

.INPUTS
None

.OUTPUTS
PSCustomObject

.NOTES
Requires elevated privileges.
Requires active enforcement state.
#>
function Start-RdpWatchdog {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [switch]$Force
    )

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new(
                        'Start-RdpWatchdog requires elevated privileges. Run as Administrator.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }
    }

    process {
        if (-not (Test-EnforcementState)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'Enforcement is not active. Enable enforcement before starting watchdog.'
                    ),
                    'EnforcementNotActive',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
            )
        }

        $module = Get-Module -Name 'RDPControl'

        if (-not $module) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'RDPControl module is not loaded.'
                    ),
                    'ModuleNotLoaded',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
            )
        }

        if (-not ($Force -or $PSCmdlet.ShouldProcess('RDPControl Watchdog', 'Register Scheduled Task'))) {
            return
        }

        try {
            $modulePath = $module.ModuleBase
            $command    = "Import-Module '$modulePath\RDPControl.psd1'; if (-not (Test-EnforcementState)) { Invoke-Enforcement }"
            $argument   = "-NoProfile -NonInteractive -WindowStyle Hidden -Command `"$command`""

            $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument

            $trigger = New-WatchdogTaskTrigger

            $settingsParams = @{
                ExecutionTimeLimit = (New-TimeSpan -Minutes 5)
                MultipleInstances  = 'IgnoreNew'
                StartWhenAvailable = $true
            }

            $settings  = New-ScheduledTaskSettingsSet @settingsParams
            $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

            if (Get-WatchdogTask) {
                Unregister-ScheduledTask -TaskName 'RDPControl Watchdog' -Confirm:$false
            }

            $registerParams = @{
                Action    = $action
                Trigger   = @($trigger)
                Settings  = $settings
                Principal = $principal
            }

            Register-WatchdogTask @registerParams | Out-Null

            New-StoreAuditRecord -Operation 'Start-RdpWatchdog' -Details 'Status=Started' | Out-Null

            Write-Verbose -Message 'RDPControl Watchdog registered successfully.'

            [PSCustomObject]@{
                Status    = 'Running'
                StartedAt = (Get-Date).ToUniversalTime().ToString('o')
                TaskName  = 'RDPControl Watchdog'
                TaskPath  = '\RDPControl\'
            }
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'StartWatchdogFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    'RDPControl Watchdog'
                )
            )
        }
    }
}
