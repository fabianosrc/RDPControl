<#
.SYNOPSIS
Removes users or groups from the Remote Desktop Users local group.

.DESCRIPTION
Removes one or more local or domain accounts from the 'Remote Desktop
Users' local group. Identities that are not members are reported and
skipped.

Membership comparison is performed by SID, not by display name. This
is required for correctness in multi-domain environments, where a
short name (for example, 'Admin') may exist in more than one domain
and refer to entirely different accounts.

Identities that cannot be resolved (account does not exist, or its
domain is unreachable) are reported as non-terminating errors and
skipped; processing continues for the remaining identities. Orphaned
SIDs (as returned by Get-RdpUser for entries that no longer resolve to
an account) can be passed directly as the Identity value to remove
them from the group.

If the removal itself succeeds but writing the audit record fails,
the operation is still considered successful: a warning is written
and -PassThru (if specified) reports Status = 'Removed'. Audit
failures must never reverse or mask a removal that already happened.

Accepts array input and pipeline input.

.PARAMETER Identity
One or more account names to remove. Accepts 'Username',
'DOMAIN\Username', '.\Username', or a SID string. Leading and
trailing whitespace is trimmed.

.PARAMETER Force
Suppresses the confirmation prompt. Equivalent to -Confirm:$false.

.PARAMETER PassThru
Returns an object describing the outcome for each identity. By
default, this cmdlet does not generate output.

.EXAMPLE
PS C:\> Remove-RdpUser -Identity 'User1'

.EXAMPLE
PS C:\> Remove-RdpUser -Identity 'User1', 'DOMAIN\User2'

.EXAMPLE
PS C:\> 'User1', 'DOMAIN\User2' | Remove-RdpUser -Force

.EXAMPLE
PS C:\> Remove-RdpUser -Identity 'S-1-5-21-1111111111-2222222222-3333333333-1001' -Force

.EXAMPLE
PS C:\> Get-RdpUser | Remove-RdpUser

.EXAMPLE
PS C:\> Remove-RdpUser -Identity 'User1' -PassThru

Identity Name  Sid                                          Status  Removed
-------- ----  ---                                          ------  -------
User1    User1 S-1-5-21-1111111111-2222222222-3333333333... Removed    True

.INPUTS
System.String[]

.OUTPUTS
None by default. If -PassThru is specified, returns PSCustomObject
with Identity, Name, Sid, Status, and Removed properties. Status is
one of 'Removed', 'AlreadyRemoved', 'NotMember', or 'Failed'.
#>
function Remove-RdpUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.UnauthorizedAccessException]::new(
                    'Remove-RdpUser requires elevated privileges. ' +
                    'Run PowerShell as Administrator.'
                ),
                'ElevationRequired',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }

        # -Force suppresses confirmation prompts for this invocation only.
        # Scoped to the function via 'local:' so it cannot leak to the
        # caller's session. The standard ConfirmPreference mechanism is
        # used rather than bypassing ShouldProcess directly, preserving
        # -WhatIf and transcript/audit behavior. An explicit -Confirm
        # always takes precedence over -Force, per PowerShell semantics.
        if ($Force -and -not $PSBoundParameters.ContainsKey('Confirm')) {
            $Local:ConfirmPreference = 'None'
        }

        # This cmdlet performs its own error handling via try/catch and
        # reports failures as non-terminating errors through
        # $PSCmdlet.WriteError(), so that processing can continue with the
        # remaining identities. The module sets $ErrorActionPreference =
        # 'Stop' globally so that *unhandled* errors fail loudly; within
        # this cmdlet, errors ARE handled, so 'Stop' is overridden locally
        # to 'Continue'. Without this, WriteError's non-terminating errors
        # would be escalated to terminating errors by the inherited 'Stop'
        # preference, discarding the ErrorId/Category set above and
        # aborting the foreach loop after the first failure. An explicit
        # -ErrorAction supplied by the caller (e.g. -ErrorAction Stop)
        # still takes precedence, since $PSBoundParameters always wins
        # over a preference variable.
        if (-not $PSBoundParameters.ContainsKey('ErrorAction')) {
            $Local:ErrorActionPreference = 'Continue'
        }

        try {
            $existingSids = Get-RdpMembershipCache

            if ($null -eq $existingSids) {
                throw 'Membership cache is null.'
            }

            if (-not ($existingSids -is [System.Collections.Generic.HashSet[string]])) {
                $cacheType = $existingSids.GetType().FullName

                throw (
                    "Expected membership cache type " +
                    "[HashSet[string]], received '$cacheType'."
                )
            }
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'MembershipCacheInitializationFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $null
                )
            )
        }

        # Track distinct SIDs already processed within this invocation so a
        # -PassThru result is emitted exactly once per logical pipeline
        # item, even though duplicates are skipped before reaching
        # Remove-LocalGroupMember.
        $processedSids = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }

    process {
        foreach ($idValue in $Identity) {

            if ([string]::IsNullOrWhiteSpace($idValue)) {
                continue
            }

            $id = $idValue.Trim()

            $resolved = Resolve-RdpIdentity -Identity $id

            if (-not $resolved.IsResolved) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new($resolved.ErrorMessage),
                    'RemoveRdpUserIdentityNotResolved',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $id
                )

                $PSCmdlet.WriteError($err)

                if ($PassThru) {
                    [PSCustomObject]@{
                        Identity = $id
                        Name     = $null
                        Sid      = $null
                        Status   = 'Failed'
                        Removed  = $false
                    }
                }

                continue
            }

            $sid = $resolved.Sid

            $targetDescription = if ([string]::IsNullOrWhiteSpace($resolved.Name)) {
                $sid
            } else {
                "$($resolved.Name) [$sid]"
            }

            if ($processedSids.Contains($sid)) {
                Write-Verbose -Message (
                    "[$id] resolves to a SID already processed in this " +
                    "invocation. Skipping."
                )

                if ($PassThru) {
                    [PSCustomObject]@{
                        Identity = $id
                        Name     = $resolved.Name
                        Sid      = $sid
                        Status   = 'AlreadyRemoved'
                        Removed  = $true
                    }
                }

                continue
            }

            if (-not $existingSids.Contains($sid)) {
                $message = "[$id] is not a member of Remote Desktop Users. Skipping."

                Write-Information -MessageData $message -Tags 'RDPControl'
                Write-Verbose -Message $message

                if ($PassThru) {
                    [PSCustomObject]@{
                        Identity = $id
                        Name     = $resolved.Name
                        Sid      = $sid
                        Status   = 'NotMember'
                        Removed  = $false
                    }
                }

                continue
            }

            [void]$processedSids.Add($sid)

            if (-not $PSCmdlet.ShouldProcess('Remote Desktop Users', "Remove $targetDescription")) {
                Write-Verbose -Message "[$id] skipped by user confirmation."
                continue
            }

            try {
                Remove-LocalGroupMember -Group 'Remote Desktop Users' -Member $sid

                [void]$existingSids.Remove($sid)

                try {
                    $storeAuditRecordParams = @{
                        Operation = 'Remove-RdpUser'
                        Details   = "Identity=$id;Sid=$sid;Action=Removed"
                    }

                    New-StoreAuditRecord @storeAuditRecordParams | Out-Null
                } catch {
                    Write-Warning -Message "Audit logging failed for identity '$id': $($_.Exception.Message)"
                }

                Write-Verbose -Message "[$id] removed from Remote Desktop Users."

                if ($PassThru) {
                    [PSCustomObject]@{
                        Identity = $id
                        Name     = $resolved.Name
                        Sid      = $sid
                        Status   = 'Removed'
                        Removed  = $true
                    }
                }
            } catch {

                # MemberNotFoundException indicates another process removed
                # the member after the cache check; treat as a benign race
                # condition. Detected by type-name comparison rather than a
                # typed catch clause, since the concrete type is only
                # guaranteed loaded when Microsoft.PowerShell.Commands.
                # Management is present.
                if ($_.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.MemberNotFoundException') {
                    [void]$existingSids.Remove($sid)

                    Write-Verbose -Message "[$id] was already removed concurrently."

                    if ($PassThru) {
                        [PSCustomObject]@{
                            Identity = $id
                            Name     = $resolved.Name
                            Sid      = $sid
                            Status   = 'AlreadyRemoved'
                            Removed  = $true
                        }
                    }

                    continue
                }

                $category = if ($_.Exception -is [System.UnauthorizedAccessException]) {
                    [System.Management.Automation.ErrorCategory]::PermissionDenied
                } else {
                    [System.Management.Automation.ErrorCategory]::InvalidOperation
                }

                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new($_.Exception.Message),
                    'RemoveRdpUserFailed',
                    $category,
                    $id
                )

                $PSCmdlet.WriteError($err)

                if ($PassThru) {
                    [PSCustomObject]@{
                        Identity = $id
                        Name     = $resolved.Name
                        Sid      = $sid
                        Status   = 'Failed'
                        Removed  = $false
                    }
                }
            }
        }
    }
}
