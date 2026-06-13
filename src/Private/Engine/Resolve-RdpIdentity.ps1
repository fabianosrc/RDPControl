<#
.SYNOPSIS
Resolves an account or group identity string to its SID and canonical
name/domain.

.DESCRIPTION
Accepts a local or domain account/group identity in any of the
following formats and resolves it to a canonical SID:

    'Username'
    'DOMAIN\Username'
    '.\Username'
    'S-1-5-21-...-1234' (SID string)

This function does not throw on resolution failure. Instead it returns
a result object with 'IsResolved = $false', so callers can decide how
to handle unresolvable identities (for example, WriteError and continue
processing the remaining pipeline items).

Exists to centralize identity resolution so that Add-RdpUser and
Remove-RdpUser compare group membership by SID rather than by display
name, which is the only identifier that is unambiguous across local
accounts, multiple domains, and accounts with colliding short names.

.PARAMETER Identity
The account or group identity to resolve.

.EXAMPLE
PS C:\> Resolve-RdpIdentity -Identity 'User1'

.EXAMPLE
PS C:\> Resolve-RdpIdentity -Identity 'DOMAIN\User2'

.EXAMPLE
PS C:\> Resolve-RdpIdentity -Identity 'S-1-5-21-1111111111-2222222222-3333333333-1001'

.INPUTS
None

.OUTPUTS
PSCustomObject with properties:
    OriginalIdentity [string]  - the identity exactly as supplied
    IsResolved       [bool]    - $true if resolution succeeded
    Sid              [string]  - canonical SID value, or $null if unresolved
    Name             [string]  - account name without domain prefix, or $null
    Domain           [string]  - account domain or local computer name, or $null
    ErrorMessage     [string]  - failure reason, or $null if resolved
#>
function Resolve-RdpIdentity {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingEmptyCatchBlock',
        '',
        Justification = 'ArgumentException indicates the input is not a SID and NTAccount resolution will be attempted next.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity
    )

    $result = [ordered]@{
        OriginalIdentity = $Identity
        IsResolved       = $false
        Sid              = $null
        Name             = $null
        Domain           = $null
        ErrorMessage     = $null
    }

    # Attempt 1: treat the input as a SID string.
    try {
        $sid = [System.Security.Principal.SecurityIdentifier]::new($Identity)

        try {
            $account = $sid.Translate([System.Security.Principal.NTAccount])
            $parts = $account.Value -split '\\', 2

            $result.IsResolved = $true
            $result.Sid        = $sid.Value
            $result.Domain     = if ($parts.Count -eq 2) { $parts[0] } else { $env:COMPUTERNAME }
            $result.Name       = if ($parts.Count -eq 2) { $parts[1] } else { $account.Value }

            return [PSCustomObject]$result
        } catch [System.Security.Principal.IdentityNotMappedException] {
            # Valid SID syntax, but no account/group maps to it (orphaned SID).
            $result.IsResolved   = $true
            $result.Sid          = $sid.Value
            $result.Name         = $sid.Value
            $result.Domain       = $null

            return [PSCustomObject]$result
        }
    } catch [System.ArgumentException] {
        # Not a valid SID string; fall through to NTAccount resolution.
    }

    # Attempt 2: treat the input as an account/group name ('Name',
    # 'DOMAIN\Name', or '.\Name').
    $normalizedIdentity = if ($Identity.StartsWith('.\')) {
        $Identity.Substring(2)
    } else {
        $Identity
    }

    try {
        $account = [System.Security.Principal.NTAccount]::new($normalizedIdentity)
        $sid     = $account.Translate([System.Security.Principal.SecurityIdentifier])

        $resolvedAccount = $sid.Translate([System.Security.Principal.NTAccount])
        $parts = $resolvedAccount.Value -split '\\', 2

        $result.IsResolved = $true
        $result.Sid        = $sid.Value
        $result.Domain     = if ($parts.Count -eq 2) { $parts[0] } else { $env:COMPUTERNAME }
        $result.Name       = if ($parts.Count -eq 2) { $parts[1] } else { $resolvedAccount.Value }

        return [PSCustomObject]$result
    } catch [System.Security.Principal.IdentityNotMappedException] {
        $result.ErrorMessage = "The identity '$Identity' could not be found."
    } catch {
        $result.ErrorMessage = "Failed to resolve identity '$Identity': $($_.Exception.Message)"
    }

    return [PSCustomObject]$result
}
