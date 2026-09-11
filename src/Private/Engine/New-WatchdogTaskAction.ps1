<#
.SYNOPSIS
Creates the action for the RDPControl Watchdog scheduled task.

.DESCRIPTION
Builds the scheduled task action that runs one watchdog cycle: Windows
PowerShell, non-interactive, imports the module from the given path and
calls the exported Invoke-RdpWatchdog with confirmation suppressed.

Only exported commands may appear in the command; private functions do
not exist in the task's own PowerShell process. The error action
preference is set to Stop so that any failure, including a failed module
import, exits non-zero and shows up as LastTaskResult. The execution
policy is overridden because SYSTEM is subject to the LocalMachine
policy, which is Restricted on Windows client editions.

Exists as a wrapper to isolate ScheduledTasks dependencies from business
logic and allow unit testing without real CimInstance objects.

.PARAMETER ModulePath
The module base directory that contains RDPControl.psd1.

.EXAMPLE
PS C:\> New-WatchdogTaskAction -ModulePath 'C:\Program Files\WindowsPowerShell\Modules\RDPControl'

.INPUTS
None

.OUTPUTS
Microsoft.Management.Infrastructure.CimInstance
#>
function New-WatchdogTaskAction {
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    [Diagnostics.CodeAnalysis.SuppressMessage(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Builds a client-only action object in memory; no system state is changed.'
    )]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModulePath
    )

    # Backticks keep $ErrorActionPreference and $false literal so they are
    # evaluated by the task process instead of while building this string.
    $command = (
        "`$ErrorActionPreference = 'Stop'; " +
        "Import-Module '$ModulePath\RDPControl.psd1'; " +
        "Invoke-RdpWatchdog -Confirm:`$false"
    )

    $argument = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$command`""

    New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument -ErrorAction Stop
}
