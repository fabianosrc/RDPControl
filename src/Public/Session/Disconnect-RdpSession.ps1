<#
.SYNOPSIS
Disconnects an active Remote Desktop session.

.DESCRIPTION
Disconnects the specified Remote Desktop session on the local machine without
terminating it. The session remains active on the server and the user can
reconnect later to resume the session state.

This operation uses the underlying Windows `rwinsta.exe` command.

For safety reasons, disconnecting the current session requires explicit
confirmation and cannot be bypassed unless -Force is specified.

The cmdlet supports pipeline input from Get-RdpSession.

.PARAMETER SessionId
Specifies the ID of the session to disconnect.

This parameter accepts input from the pipeline by property name.

.PARAMETER Force
Bypasses confirmation prompts for non-current sessions.

Note: Current session protection still requires ShouldProcess confirmation.

.EXAMPLE
PS C:\> Disconnect-RdpSession -SessionId 3

Disconnects session ID 3 after confirmation.

.EXAMPLE
PS C:\> Get-RdpSession -UserName 'User1' | Disconnect-RdpSession

Disconnects all sessions belonging to User1.

.EXAMPLE
PS C:\> Disconnect-RdpSession -SessionId 3 -Force

Forces disconnection of session 3 without confirmation prompts.

.INPUTS
System.Int32

.OUTPUTS
None

.NOTES
Requires elevated privileges.
Uses rwinsta.exe as the underlying system command.
Session identity resolution is based on active session lookup.
#>

function Disconnect-RdpSession {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$SessionId,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.UnauthorizedAccessException]::new(
                    'Disconnect-RdpSession requires elevated privileges. Run PowerShell as Administrator.'
                ),
                'ElevationRequired',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $SessionId
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }

        $currentSessionId = (Get-RdpSession |
            Where-Object { $_.UserName -eq $env:USERNAME -and $_.State -eq 'Active' } |
            Select-Object -First 1 -ExpandProperty SessionId
        )
    }

    process {
        $isCurrentSession = ($SessionId -eq $currentSessionId)

        if ($isCurrentSession -and -not $Force) {
            if (-not $PSCmdlet.ShouldProcess("Session [$SessionId]", 'Disconnect current session')) {
                return
            }
        } elseif (-not $PSCmdlet.ShouldProcess("Session [$SessionId]", 'Disconnect session')) {
            return
        }

        try {
            $result = & rwinsta.exe $SessionId 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "rwinsta.exe failed for session [$SessionId]: $result"
            }

            Write-Verbose -Message "Session [$SessionId] disconnected successfully."
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'DisconnectRdpSessionFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $SessionId
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
