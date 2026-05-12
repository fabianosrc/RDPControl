<#
.SYNOPSIS
Lists active Remote Desktop sessions.

.DESCRIPTION
Returns active RDP sessions on the local machine using qwinsta.
Optionally filters by username.

.PARAMETER UserName
Filters sessions by username.

.EXAMPLE
PS C:\> Get-RdpSession

.EXAMPLE
PS C:\> Get-RdpSession -UserName 'User1'

.INPUTS
None

.OUTPUTS
PSCustomObject[] with properties:
    SessionId   [int]    - session identifier
    UserName    [string] - logged-in username
    State       [string] - session state (Active, Disconnected, etc.)
    SessionName [string] - session name (e.g. rdp-tcp#1)
#>
function Get-RdpSession {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [string]$UserName
    )

    begin {
        Assert-RdpEnvironment
    }

    process {
        try {
            $output = & qwinsta.exe 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "qwinsta.exe failed with exit code $LASTEXITCODE"
            }

            $sessions = foreach ($line in $output) {
                if ([string]::IsNullOrWhiteSpace($line)) {
                    continue
                }

                if ($line -match 'SESSIONNAME|USERNAME|ID\s+STATE') {
                    continue
                }

                if ($line -match '^\s*(\S+)\s+(\S*)\s+(\d+)\s+(\S+)\s*$') {
                    $sessionName = $Matches[1]
                    $user        = $Matches[2]
                    $sessionId   = [int]$Matches[3]
                    $state       = $Matches[4]

                    if (-not $user) {
                        $user = $null
                    }

                    [PSCustomObject]@{
                        SessionName = $sessionName
                        UserName    = $user
                        SessionId   = $sessionId
                        State       = $state
                    }
                }
            }

            if ($UserName) {
                $sessions = $sessions |
                    Where-Object { $_.UserName -and $_.UserName -eq $UserName }
            }

            $sessions
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'GetRdpSessionFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                'qwinsta'
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
