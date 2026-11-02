<#
.SYNOPSIS
Runs one RDPControl watchdog cycle.

.DESCRIPTION
Checks whether the enforcement state is intact and re-applies enforcement
when it is not. The RDPControl Watchdog scheduled task runs this cmdlet at
every boot. It can also be run manually to verify or repair the state
without waiting for a reboot.

Nothing is changed while the target binary matches the most recent
enforced snapshot (Action = 'None'). Otherwise enforcement is re-applied
through the same workflow as Set-RdpSessionMode -Enabled and an audit
record is written (Action = 'Reapplied'). Failures are recorded in the
audit store and re-thrown so that a scheduled run exits with a non-zero
result.

.EXAMPLE
PS C:\> Invoke-RdpWatchdog

.EXAMPLE
PS C:\> Invoke-RdpWatchdog -Confirm:$false

.EXAMPLE
PS C:\> Invoke-RdpWatchdog -WhatIf

.INPUTS
None

.OUTPUTS
RDPControl.WatchdogRunResult

Contains:
- Action      [string] - 'None' or 'Reapplied'
- Enforced    [bool]   - enforcement state after the run
- Hash        [string] - SHA256 of the enforced binary when re-applied
- SnapshotId  [long]   - ID of the pre-enforcement snapshot when re-applied
- WriteOffset [string] - hex offset written when re-applied
- CheckedAt   [string] - ISO 8601 UTC timestamp

.NOTES
Requires elevated privileges.
#>
function Invoke-RdpWatchdog {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('RDPControl.WatchdogRunResult')]
    param ()

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new(
                        'Invoke-RdpWatchdog requires elevated privileges. Run as Administrator.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }

        $targetPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\termsrv.dll'
    }

    process {
        if (Test-EnforcementState) {
            Write-Verbose -Message 'Enforcement state is intact. No action required.'

            return [PSCustomObject]@{
                PSTypeName  = 'RDPControl.WatchdogRunResult'
                Action      = 'None'
                Enforced    = $true
                Hash        = $null
                SnapshotId  = $null
                WriteOffset = $null
                CheckedAt   = (Get-Date).ToUniversalTime().ToString('o')
            }
        }

        if (-not $PSCmdlet.ShouldProcess($targetPath, 'Re-apply enforcement')) {
            return
        }

        try {
            # This cmdlet is the confirmation gate; suppress the nested prompt.
            $result = Invoke-Enforcement -Confirm:$false
        } catch {
            $failure = $_

            try {
                $details = "Result=Failed;Error=$($failure.Exception.Message)"

                New-StoreAuditRecord -Operation 'Invoke-RdpWatchdog' -Details $details | Out-Null
            } catch {
                Write-Warning -Message "Failed to write watchdog audit record: $($_.Exception.Message)"
            }

            if ($failure -is [System.Management.Automation.ErrorRecord]) {
                $PSCmdlet.ThrowTerminatingError($failure)
            }

            throw $failure
        }

        New-StoreAuditRecord -Operation 'Invoke-RdpWatchdog' -Details "Result=Reapplied;Hash=$($result.Hash)" | Out-Null

        [PSCustomObject]@{
            PSTypeName  = 'RDPControl.WatchdogRunResult'
            Action      = 'Reapplied'
            Enforced    = $true
            Hash        = $result.Hash
            SnapshotId  = $result.SnapshotId
            WriteOffset = $result.WriteOffset
            CheckedAt   = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
