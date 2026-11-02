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
    LastResult [string] - outcome of the last run: 'Success', 'Running',
                          'NeverRun', 'Failed (0x...)', or $null when unknown
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
                Status     = 'NotRegistered'
                LastRun    = $null
                NextRun    = $null
                LastResult = $null
                CheckedAt  = (Get-Date).ToUniversalTime().ToString('o')
            }
        }

        $taskInfo = Get-WatchdogTaskInfo -Task $task

        $status = if ($task.State -eq 'Ready' -or $task.State -eq 'Running') {
            'Running'
        } else {
            'Stopped'
        }

        [PSCustomObject]@{
            Status     = $status
            LastRun    = Get-WatchdogTimestamp -TaskInfo $taskInfo -PropertyName 'LastRunTime'
            NextRun    = Get-WatchdogTimestamp -TaskInfo $taskInfo -PropertyName 'NextRunTime'
            LastResult = Get-WatchdogTaskResult -TaskInfo $taskInfo
            CheckedAt  = (Get-Date).ToUniversalTime().ToString('o')
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

<#
.SYNOPSIS
Translates the LastTaskResult of a task info object into a status string.

.DESCRIPTION
Returns $null if the task info object is $null, the property does not
exist, or the property value is $null. Otherwise maps the Task Scheduler
result code to 'Success' (0), 'Running' (0x41301), 'NeverRun' (0x41303)
or 'Failed (0x...)' for any other code, including PowerShell exit code 1
and HRESULT values.

.PARAMETER TaskInfo
The task info object returned by Get-WatchdogTaskInfo. May be $null.

.OUTPUTS
System.String or $null
#>
function Get-WatchdogTaskResult {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()]
        [object]$TaskInfo
    )

    if ($null -eq $TaskInfo) {
        return $null
    }

    $property = $TaskInfo.PSObject.Properties['LastTaskResult']

    if ($null -eq $property -or $null -eq $property.Value) {
        return $null
    }

    # LastTaskResult is a UInt32; widen so HRESULT values format correctly.
    $code = [int64]$property.Value

    switch ($code) {
        0       { return 'Success' }
        267009  { return 'Running' }
        267011  { return 'NeverRun' }
        default { return ('Failed (0x{0:X})' -f $code) }
    }
}
