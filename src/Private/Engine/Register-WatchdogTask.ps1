<#
.SYNOPSIS
Registers the RDPControl Watchdog scheduled task.

.DESCRIPTION
Wraps Register-ScheduledTask to register the RDPControl Watchdog task
with the given action, triggers, settings, and principal.

Exists as a wrapper to isolate ScheduledTasks dependencies from business
logic and allow unit testing without real CimInstance objects.

This is an internal wrapper invoked only by Start-RdpWatchdog, which
already implements ShouldProcess for this operation.

.PARAMETER Action
The scheduled task action.

.PARAMETER Trigger
The scheduled task triggers.

.PARAMETER Settings
The scheduled task settings.

.PARAMETER Principal
The scheduled task principal.

All parameters are typed as [object]/[object[]] (rather than
CimInstance/CimInstance[]) so that mocked objects (e.g. PSCustomObject)
can be used in unit tests.

.EXAMPLE
PS C:\> Register-WatchdogTask -Action $action -Trigger $triggers -Settings $settings -Principal $principal

.INPUTS
None

.OUTPUTS
Microsoft.Management.Infrastructure.CimInstance
#>
function Register-WatchdogTask {
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Action,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Trigger,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Settings,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Principal
    )

    $registerParams = @{
        TaskName  = 'RDPControl Watchdog'
        TaskPath  = '\RDPControl\'
        Action    = $Action
        Trigger   = $Trigger
        Settings  = $Settings
        Principal = $Principal
    }

    Register-ScheduledTask @registerParams -ErrorAction Stop
}
