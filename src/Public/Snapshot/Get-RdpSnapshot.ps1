<#
.SYNOPSIS
Lists stored binary snapshots.

.DESCRIPTION
Returns snapshot records from the store.

By default, only pre-enforcement snapshots are returned. These are the
valid restore points that can be used with Restore-RdpSnapshot.

Use -All to include enforced snapshots, which are stored internally
for integrity validation by the watchdog and enforcement engine.

.PARAMETER Id
Returns the snapshot with the specified ID.

.PARAMETER Latest
Returns the most recent pre-enforcement snapshot.

.PARAMETER All
Returns all snapshots, including enforced snapshots.

.PARAMETER Top
Limits the number of returned records.

.EXAMPLE
PS C:\> Get-RdpSnapshot

.EXAMPLE
PS C:\> Get-RdpSnapshot -Latest

.EXAMPLE
PS C:\> Get-RdpSnapshot -Id 1

.EXAMPLE
PS C:\> Get-RdpSnapshot -Top 5

.EXAMPLE
PS C:\> Get-RdpSnapshot -All

.INPUTS
None

.OUTPUTS
RDPControl.SnapshotInfo
#>
function Get-RdpSnapshot {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType('RDPControl.SnapshotInfo')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [Parameter(Mandatory, ParameterSetName = 'Latest')]
        [switch]$Latest,

        [Parameter(ParameterSetName = 'Default')]
        [switch]$All,

        [Parameter(ParameterSetName = 'Default')]
        [ValidateRange(1, 1000)]
        [int]$Top
    )

    begin {
        Assert-RdpEnvironment
    }

    process {
        $params = @{}

        # Default behavior: restore points only (enforced = false)
        if (-not $All) {
            $params.Enforced = $false
        }

        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $params.Id = $Id
        }

        if ($Latest) {
            $params.Latest = $true
        }

        if ($PSBoundParameters.ContainsKey('Top')) {
            $params.Top = $Top
        }

        Get-StoreSnapshot @params
    }
}
