<#
.SYNOPSIS
Builds a SID-based membership cache for the Remote Desktop Users group.

.DESCRIPTION
Returns a HashSet of the SIDs of all current members of the
'Remote Desktop Users' local group, using ordinal case-insensitive
comparison.

Used by Add-RdpUser and Remove-RdpUser to determine membership without
repeatedly enumerating the group, and to perform O(1) membership checks
by SID rather than by display name (which is ambiguous across domains).

.EXAMPLE
PS C:\> $cache = Get-RdpMembershipCache
PS C:\> $cache.Contains('S-1-5-21-1111111111-2222222222-3333333333-1001')

.INPUTS
None

.OUTPUTS
System.Collections.Generic.HashSet[string]
#>
function Get-RdpMembershipCache {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[string]])]
    param ()

    $cache = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    Get-RdpUser | ForEach-Object { [void]$cache.Add($_.SID) }

    return $cache
}
