<#
.SYNOPSIS
Retrieves run-time information for a scheduled task.

.DESCRIPTION
Wraps Get-ScheduledTaskInfo to retrieve last/next run times for the
given scheduled task.

Exists as a wrapper to isolate ScheduledTasks dependencies from business
logic and allow unit testing without a registered scheduled task.

.PARAMETER Task
The scheduled task object returned by Get-WatchdogTask. Must not be
$null. Typed as [object] (rather than CimInstance) so that mocked
task objects (e.g. PSCustomObject) can be used in unit tests.

.EXAMPLE
PS C:\> $task = Get-WatchdogTask
PS C:\> Get-WatchdogTaskInfo -Task $task

.INPUTS
None

.OUTPUTS
Microsoft.Management.Infrastructure.CimInstance
#>
function Get-WatchdogTaskInfo {
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Task
    )

    Get-ScheduledTaskInfo -InputObject $Task -ErrorAction Stop
}
