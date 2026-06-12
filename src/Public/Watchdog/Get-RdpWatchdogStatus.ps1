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
        $task = Get-WatchdogTask

        if ($null -eq $task) {
            return [PSCustomObject]@{
                Status    = 'NotRegistered'
                LastRun   = $null
                NextRun   = $null
                CheckedAt = (Get-Date).ToUniversalTime().ToString('o')
            }
        }

        $taskInfo = Get-WatchdogTaskInfo -Task $task

        $status = if ($task.State -eq 'Ready' -or $task.State -eq 'Running') {
            'Running'
        } else {
            'Stopped'
        }

        [PSCustomObject]@{
            Status    = $status
            LastRun   = Get-WatchdogTimestamp -TaskInfo $taskInfo -PropertyName 'LastRunTime'
            NextRun   = Get-WatchdogTimestamp -TaskInfo $taskInfo -PropertyName 'NextRunTime'
            CheckedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}

<#
.SYNOPSIS
Safely extracts and formats a timestamp property from a task info object.

.DESCRIPTION
Returns $null if the task info object is $null, the property does not
exist, or the property value is $null. Otherwise returns the value
formatted as an ISO 8601 UTC string.

.PARAMETER TaskInfo
The task info object returned by Get-WatchdogTaskInfo. May be $null.

.PARAMETER PropertyName
The name of the timestamp property to extract.

.OUTPUTS
System.String or $null
#>
function Get-WatchdogTimestamp {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()]
        [object]$TaskInfo,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    if ($null -eq $TaskInfo) {
        return $null
    }

    $property = $TaskInfo.PSObject.Properties[$PropertyName]

    if ($null -eq $property -or $null -eq $property.Value) {
        return $null
    }

    return $property.Value.ToUniversalTime().ToString('o')
}
