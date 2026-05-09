<#
.SYNOPSIS
Returns the current multi-session enforcement state.

.DESCRIPTION
Checks whether the multi-session connection policy is currently active
by comparing the target binary hash against the most recent enforced snapshot.

.EXAMPLE
PS C:\> Get-RdpMultiSession

.INPUTS
None

.OUTPUTS
PSCustomObject with properties:
    Enforced  [bool]   - whether multi-session is currently configured
    Hash      [string] - current binary SHA256
    CheckedAt [string] - ISO 8601 UTC timestamp
#>
function Get-RdpMultiSession {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param ()

    begin {
        Assert-RdpEnvironment
    }

    process {
        $isEnforced = Test-EnforcementState

        [PSCustomObject]@{
            Enforced  = $isEnforced
            CheckedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
