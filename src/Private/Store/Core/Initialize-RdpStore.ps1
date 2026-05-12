<#
.SYNOPSIS
Initializes the RDPControl store.

.DESCRIPTION
Orchestrates store initialization using the active provider.
Responsible for policy enforcement and execution control only.

.EXAMPLE
PS C:\> Initialize-RdpStore

.OUTPUTS
None
#>
<#
.SYNOPSIS
Initializes the RDPControl store.

.DESCRIPTION
Internal orchestration entry point for store initialization.
Executed by higher-level policy or automation flows.
Not intended for direct user interaction.

.EXAMPLE
Initialize-RdpStore

.OUTPUTS
None
#>
function Initialize-RdpStore {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param ()

    begin {
        Assert-RdpEnvironment
    }

    process {
        if (-not $PSCmdlet.ShouldProcess('RDPControl Store', 'Initialize')) {
            return
        }

        Initialize-SQLiteProvider
    }
}
