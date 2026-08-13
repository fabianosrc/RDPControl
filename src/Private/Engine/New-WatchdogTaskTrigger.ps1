<#
.SYNOPSIS
Creates the boot trigger for the RDPControl Watchdog scheduled task.

.DESCRIPTION
Builds an at-startup scheduled task trigger with a short delay so that
services and the network stack are available before enforcement is
re-applied.

A boot trigger is used instead of a Windows Update event subscription
because Windows Update reverts changes across a reboot in ways that do
not reliably raise a subscribable event, while every servicing operation
that matters ends in a restart.

Exists as a wrapper to isolate ScheduledTasks dependencies from business
logic and allow unit testing without real CimInstance objects.

.PARAMETER Delay
The delay after boot before the task runs, as an ISO 8601 duration.
Defaults to 'PT30S' (30 seconds).

.EXAMPLE
PS C:\> New-WatchdogTaskTrigger

.EXAMPLE
PS C:\> New-WatchdogTaskTrigger -Delay 'PT5M'

.INPUTS
None

.OUTPUTS
Microsoft.Management.Infrastructure.CimInstance
#>
function New-WatchdogTaskTrigger {
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    [Diagnostics.CodeAnalysis.SuppressMessage(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Builds a client-only trigger object in memory; no system state is changed.'
    )]
    param (
        [Parameter()]
        [ValidatePattern('^P(?!$)(\d+Y)?(\d+M)?(\d+D)?(T(?=\d)(\d+H)?(\d+M)?(\d+S)?)?$')]
        [string]$Delay = 'PT30S'
    )

    $trigger = New-ScheduledTaskTrigger -AtStartup -ErrorAction Stop

    $trigger.Delay = $Delay

    $trigger
}
