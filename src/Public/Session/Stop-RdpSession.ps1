<#
.SYNOPSIS
Terminates an active Remote Desktop session.

.DESCRIPTION
Forces logoff of a specified Remote Desktop Services session on the local machine.

This operation immediately ends all processes running in the target session.
Any unsaved data in that session will be lost.

The cmdlet supports pipeline input from Get-RdpSession.

For safety reasons, terminating the current session requires explicit confirmation,
and cannot be bypassed unless -Force is specified.

.PARAMETER SessionId
Specifies the ID of the session to terminate.

Accepts input from pipeline by property name.

.PARAMETER Force
Bypasses confirmation prompts for non-current sessions.

Note: Current session termination still requires explicit ShouldProcess approval.

.EXAMPLE
PS C:\> Stop-RdpSession -SessionId 3

Terminates session ID 3 after confirmation.

.EXAMPLE
PS C:\> Get-RdpSession | Stop-RdpSession

Terminates sessions returned from Get-RdpSession pipeline.

.EXAMPLE
PS C:\> Stop-RdpSession -SessionId 3 -Force

Forces termination of session 3 without confirmation.

.INPUTS
System.Int32

.OUTPUTS
None

.NOTES
Requires elevated privileges.
Uses logoff.exe as underlying system command.
#>

function Stop-RdpSession {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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
                    'Stop-RdpSession requires elevated privileges. Run PowerShell as Administrator.'
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
            if (-not $PSCmdlet.ShouldProcess("Session [$SessionId]", 'Terminate current session')) {
                return
            }
        } elseif (-not $PSCmdlet.ShouldProcess("Session [$SessionId]", 'Terminate session')) {
            return
        }

        try {
            $result = & logoff.exe $SessionId 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "logoff.exe failed for session [$SessionId]: $result"
            }

            Write-Verbose -Message "Session [$SessionId] terminated successfully."
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'StopRdpSessionFailed',
                [System.Management.Automation.ErrorCategory]::WriteError, @{
                    SessionId = $SessionId
                }
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
