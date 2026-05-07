<#
.SYNOPSIS
Tests whether the current user session is an active RDP connection.

.DESCRIPTION
Queries the current session environment to determine if the user is connected
via Remote Desktop Protocol. Uses the SESSIONNAME environment variable, which
is set to 'Console' for local sessions and 'RDP-Tcp#N' for remote sessions.

.EXAMPLE
if (Test-IsRdpSession) { Write-Warning -Message 'You are connected via RDP.' }

.OUTPUTS
System.Boolean
#>
function Test-IsRdpSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    $sessionName = [System.Environment]::GetEnvironmentVariable('SESSIONNAME')

    if ([string]::IsNullOrEmpty($sessionName)) {
        return $false
    }

    return $sessionName -like 'RDP-Tcp*'
}
