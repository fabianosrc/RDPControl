<#
.SYNOPSIS
Retrieves snapshot records from the store.

.DESCRIPTION
Store Core contract for snapshot queries. Delegates to the active provider.

.PARAMETER Id
Returns the snapshot with the specified ID.

.PARAMETER Sha256
Returns the snapshot matching the specified SHA256 hash.

.PARAMETER Enforced
Filters by enforced state.

.PARAMETER Latest
Returns only the most recent snapshot.

.PARAMETER Top
Returns the specified number of most recent snapshots.

.EXAMPLE
PS C:\> Get-StoreSnapshot -Latest

.EXAMPLE
PS C:\> Get-StoreSnapshot -Enforced $true

.OUTPUTS
PSCustomObject[]
#>
function Get-StoreSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter()]
        [int]$Id,
        [Parameter()]
        [string]$Sha256,

        [Parameter()]
        [bool]$Enforced,

        [Parameter()]
        [switch]$Latest,

        [Parameter()]
        [int]$Top
    )

    begin {
        Assert-RdpEnvironment
    }

    process {
        Get-SQLiteSnapshot @PSBoundParameters
    }
}
