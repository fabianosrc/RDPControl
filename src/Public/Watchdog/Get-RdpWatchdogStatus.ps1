<#
.SYNOPSIS
Returns the current RDPControl watchdog state.

.DESCRIPTION
Checks whether the RDPControl Watchdog scheduled task is registered
and returns its current status.

.EXAMPLE
PS C:\> Get-RdpWatchdogStatus

.INPUTS
None

.OUTPUTS
PSCustomObject with properties:
    Status    [string] - 'Running', 'Stopped', or 'NotRegistered'
    LastRun   [string] - last run time (ISO 8601 UTC), or $null
    NextRun   [string] - next scheduled run (ISO 8601 UTC), or $null
    CheckedAt [string] - ISO 8601 UTC timestamp
#>
function Get-RdpWatchdogStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param ()

    begin {
        Assert-RdpEnvironment
    }

    process {
        $taskName = 'RDPControl Watchdog'
        $taskPath = '\RDPControl\'

        $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

        if ($null -eq $task) {
            return [PSCustomObject]@{
                Status    = 'NotRegistered'
                LastRun   = $null
                NextRun   = $null
                CheckedAt = (Get-Date).ToUniversalTime().ToString('o')
            }
        }

        $taskInfo = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue

        $status = if ($task.State -eq 'Ready' -or $task.State -eq 'Running') {
            'Running'
        } else {
            'Stopped'
        }

        $lastRun = if ($null -ne $taskInfo.LastRunTime) {
            $taskInfo.LastRunTime.ToUniversalTime().ToString('o')
        } else {
            $null
        }

        $nextRun = if ($null -ne $taskInfo.NextRunTime) {
            $taskInfo.NextRunTime.ToUniversalTime().ToString('o')
        } else {
            $null
        }

        [PSCustomObject]@{
            Status    = $status
            LastRun   = $lastRun
            NextRun   = $nextRun
            CheckedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
