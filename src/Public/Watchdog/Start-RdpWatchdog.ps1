<#
.SYNOPSIS
Starts the RDPControl self-healing watchdog.

.DESCRIPTION
Registers a Windows Scheduled Task that monitors system integrity and
automatically re-applies enforcement when changes are detected.

The task is triggered by Windows Update events (Event ID 19 and 20 from
Microsoft-Windows-WindowsUpdateClient) and runs under the SYSTEM account.

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

        if (-not ($Force -or $PSCmdlet.ShouldProcess('RDPControl Watchdog', 'Register Scheduled Task'))) {
            return
        }

        $modulePath = (Get-Module -Name 'RDPControl').ModuleBase
        $command    = "Import-Module '$modulePath\RDPControl.psd1'; if (-not (Test-EnforcementState)) { Invoke-Enforcement }"
        $argument   = "-NoProfile -NonInteractive -WindowStyle Hidden -Command `"$command`""

        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument

        # Event-based triggers via CIM for Windows Update events
        $triggerClass = Get-CimClass -ClassName 'MSFT_TaskEventTrigger' -Namespace 'Root\Microsoft\Windows\TaskScheduler'

        $trigger19 = New-CimInstance -CimClass $triggerClass -ClientOnly -Property @{
            Enabled      = $true
            Subscription = '<QueryList><Query Id="0"><Select Path="Microsoft-Windows-WindowsUpdateClient/Operational">*[System[EventID=19]]</Select></Query></QueryList>'
        }

        $trigger20 = New-CimInstance -CimClass $triggerClass -ClientOnly -Property @{
            Enabled      = $true
            Subscription = '<QueryList><Query Id="0"><Select Path="Microsoft-Windows-WindowsUpdateClient/Operational">*[System[EventID=20]]</Select></Query></QueryList>'
        }

        $settingsParams = @{
            ExecutionTimeLimit = (New-TimeSpan -Minutes 5)
            MultipleInstances  = 'IgnoreNew'
            StartWhenAvailable = $true
        }

        $settings  = New-ScheduledTaskSettingsSet @settingsParams
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

        try {
            if (Get-ScheduledTask -TaskName 'RDPControl Watchdog' -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName 'RDPControl Watchdog' -Confirm:$false
            }

            $registerParams = @{
                TaskName  = 'RDPControl Watchdog'
                TaskPath  = '\RDPControl\'
                Action    = $action
                Trigger   = @($trigger19, $trigger20)
                Settings  = $settings
                Principal = $principal
                Force     = $true
            }

            Register-ScheduledTask @registerParams | Out-Null

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
