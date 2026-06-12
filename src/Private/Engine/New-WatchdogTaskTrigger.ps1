<#
.SYNOPSIS
Creates a CIM event trigger for the RDPControl Watchdog scheduled task.

.DESCRIPTION
Builds an MSFT_TaskEventTrigger CIM instance subscribed to the specified
Windows Update Client event ID.

Exists as a wrapper to isolate CIM dependencies from business logic and
allow unit testing without real CimClass/CimInstance objects.

.PARAMETER EventId
The Windows Update Client event ID to subscribe to. Valid values are
19 and 20 (Microsoft-Windows-WindowsUpdateClient/Operational).

.EXAMPLE
PS C:\> New-WatchdogTaskTrigger -EventId 19

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
        Justification = 'Builds a client-only CIM instance in memory; no system state is changed.'
    )]
    param (
        [Parameter(Mandatory)]
        [ValidateSet(19, 20)]
        [int]$EventId
    )

    $triggerClass = Get-CimClass -ClassName 'MSFT_TaskEventTrigger' -Namespace 'Root\Microsoft\Windows\TaskScheduler' -ErrorAction Stop

    $subscription = '<QueryList><Query Id="0"><Select Path="Microsoft-Windows-WindowsUpdateClient/Operational">' +
        "*[System[EventID=$EventId]]" +
        '</Select></Query></QueryList>'

    New-CimInstance -CimClass $triggerClass -ClientOnly -Property @{
        Enabled      = $true
        Subscription = $subscription
    } -ErrorAction Stop
}
