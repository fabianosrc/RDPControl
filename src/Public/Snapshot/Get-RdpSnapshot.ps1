<#
.SYNOPSIS
Lists stored snapshots with metadata.

.DESCRIPTION
Retrieves snapshot records from the store. Supports filtering by ID,
latest record, or limiting result set size.

.EXAMPLE
PS C:\> Get-RdpSnapshot

.EXAMPLE
PS C:\> Get-RdpSnapshot -Latest

.EXAMPLE
PS C:\> Get-RdpSnapshot -Id 3

.EXAMPLE
PS C:\> Get-RdpSnapshot -Top 5

.INPUTS
None

.OUTPUTS
PSCustomObject[]
#>

function Get-RdpSnapshot {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,

        [Parameter(Mandatory, ParameterSetName = 'Latest')]
        [switch]$Latest,

        [Parameter(ParameterSetName = 'All')]
        [ValidateRange(1, 1000)]
        [int]$Top
    )

    begin {
        Assert-RdpEnvironment
    }

    process {
        # direct parameter passthrough (cleaner + safer contract)
        $params = @{}

        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $params.Id = $Id
        }

        if ($PSCmdlet.ParameterSetName -eq 'Latest') {
            $params.Latest = $true
        }

        if ($PSCmdlet.ParameterSetName -eq 'All' -and $PSBoundParameters.ContainsKey('Top')) {
            $params.Top = $Top
        }

        Get-StoreSnapshot @params
    }
}
