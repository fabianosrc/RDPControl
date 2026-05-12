<#
.SYNOPSIS
Creates an audit record in the RDPControl store.

.DESCRIPTION
Core Store contract for audit logging. Validates execution policy
and delegates persistence to the active provider implementation.

.PARAMETER Operation
Operation name to record.

.PARAMETER Details
Optional operation details.

.EXAMPLE
New-StoreAuditRecord -Operation 'Invoke-Enforcement' -Details 'WriteOffset=0x001E815'

.OUTPUTS
System.Int64
#>

function New-StoreAuditRecord {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([long])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Operation,

        [Parameter()]
        [string]$Details
    )

    begin {
        Assert-RdpEnvironment
    }

    process {
        if (-not $PSCmdlet.ShouldProcess("Audit Record [$Operation]", "Create audit entry")) {
            return
        }

        return New-SQLiteAuditRecord -Operation $Operation -Details $Details
    }
}
