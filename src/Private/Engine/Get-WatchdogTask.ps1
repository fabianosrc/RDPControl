<#
.SYNOPSIS
Retrieves the RDPControl Watchdog scheduled task.

.DESCRIPTION
Wraps Get-ScheduledTask to retrieve the RDPControl Watchdog task by
name and path. Returns $null when the task is not registered.

Only the "task not found" condition is suppressed. Any other failure
(for example, the Task Scheduler service being unavailable) is
propagated to the caller, so operational issues are not mistaken for
an unregistered watchdog.

Exists as a wrapper to isolate ScheduledTasks dependencies from business
logic and allow unit testing without a registered scheduled task.

.PARAMETER TaskName
Name of the scheduled task. Defaults to 'RDPControl Watchdog'.

.PARAMETER TaskPath
Path of the scheduled task. Defaults to '\RDPControl\'.

.EXAMPLE
PS C:\> Get-WatchdogTask

.INPUTS
None

.OUTPUTS
Microsoft.Management.Infrastructure.CimInstance
#>
function Get-WatchdogTask {
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$TaskName = 'RDPControl Watchdog',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$TaskPath = '\RDPControl\'
    )

    try {
        Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
    } catch {
        if ($_.CategoryInfo.Category -eq 'ObjectNotFound') {
            return $null
        }

        throw
    }
}
