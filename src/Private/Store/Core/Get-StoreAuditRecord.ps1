<#
.SYNOPSIS
Retrieves audit log records from the store.

.DESCRIPTION
Core Store contract for audit log retrieval.

This function validates the RDPControl environment and delegates
record retrieval to the active persistence provider.

.PARAMETER Id
Returns the audit record with the specified identifier.

.PARAMETER Operation
Filters records by operation name.

.PARAMETER Latest
Returns only the most recent record.

.PARAMETER Top
Limits the number of returned records.

.EXAMPLE
PS C:\> Get-StoreAuditRecord -Top 10

.EXAMPLE
PS C:\> Get-StoreAuditRecord -Operation 'Invoke-Enforcement' -Latest

.OUTPUTS
PSCustomObject[]
#>
function Get-StoreAuditRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Operation,

        [Parameter()]
        [switch]$Latest,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$Top
    )

    begin {
        Assert-RdpEnvironment
    }

    process {
        Get-SQLiteAuditRecord @PSBoundParameters
    }
}
