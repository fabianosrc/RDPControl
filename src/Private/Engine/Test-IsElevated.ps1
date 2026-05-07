<#
.SYNOPSIS
Tests whether the current session is running with Administrator privileges.

.DESCRIPTION
Evaluates the current Windows identity against the built-in Administrator role.
Returns $true if elevated, $false otherwise. Does not throw on non-elevated sessions.

.EXAMPLE
if (-not (Test-IsElevated)) { throw "Elevation required." }

.OUTPUTS
System.Boolean
#>
function Test-IsElevated {
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
