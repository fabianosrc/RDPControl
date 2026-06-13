<#
.SYNOPSIS
Adds users or groups to the Remote Desktop Users local group.

.DESCRIPTION
Adds one or more local or Active Directory identities to the
Remote Desktop Users local group. Identities are resolved to
their SID before membership is evaluated, so the comparison
is correct across domains and locales.

Identities that cannot be resolved produce a non-terminating
error and processing continues with the remaining identities.
Identities that are already members are skipped with a warning.

.PARAMETER Identity
One or more identities to add. Accepts local account names,
'DOMAIN\User' or '.\User' formats, and SID strings. Accepts
pipeline input and pipeline input by property name.

.EXAMPLE
PS C:\> Add-RdpUser -Identity 'User1'

Adds the local account 'User1' to Remote Desktop Users.

.EXAMPLE
PS C:\> 'User1', 'DOMAIN\User2' | Add-RdpUser -Confirm:$false

Adds multiple identities via pipeline, suppressing confirmation prompts.

.EXAMPLE
PS C:\> Get-RdpUser | Where-Object Domain -eq 'CONTOSO' | Add-RdpUser

Re-adds all CONTOSO-domain members (no-op if already members).
#>
function Add-RdpUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity
    )

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new(
                        'Add-RdpUser requires elevated privileges. Run PowerShell as Administrator.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }

        try {
            $existingSids = Get-RdpMembershipCache

            if ($null -eq $existingSids) {
                throw 'Membership cache is null.'
            }

            if (-not ($existingSids -is [System.Collections.Generic.HashSet[string]])) {
                throw (
                    "Expected membership cache type " +
                    "[HashSet[string]], received " +
                    "'$($existingSids.GetType().FullName)'."
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
    }

    process {
        foreach ($id in $Identity) {

            if ([string]::IsNullOrWhiteSpace($id)) {
                continue
            }

            $resolved = Resolve-RdpIdentity -Identity $id

            if (-not $resolved.IsResolved) {
                $PSCmdlet.WriteError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Security.Principal.IdentityNotMappedException]::new(
                            $resolved.ErrorMessage
                        ),
                        'AddRdpUserIdentityNotResolved',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $id
                    )
                )

                continue
            }

            $targetDescription = if ($resolved.Name) {
                "$($resolved.Name) [$($resolved.Sid)]"
            } else {
                $resolved.Sid
            }

            if ($existingSids.Contains($resolved.Sid)) {
                Write-Warning -Message "Identity already present in Remote Desktop Users: $targetDescription"
                continue
            }

            if (-not $PSCmdlet.ShouldProcess($targetDescription, 'Add to Remote Desktop Users')) {
                Write-Verbose -Message "Operation cancelled by user: $targetDescription"
                continue
            }

            try {
                Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $resolved.Sid

                [void]$existingSids.Add($resolved.Sid)

                New-StoreAuditRecord -Operation 'Add-RdpUser' -Details (
                    "Identity=$id;" +
                    "ResolvedName=$($resolved.Name);" +
                    "Sid=$($resolved.Sid);" +
                    "Action=Added"
                ) | Out-Null

                Write-Verbose -Message "Added to Remote Desktop Users: $targetDescription"

            } catch [Microsoft.PowerShell.Commands.MemberExistsException] {
                # Another process may have added the member
                # after the cache check.
                [void]$existingSids.Add($resolved.Sid)
                Write-Verbose -Message "Identity was added concurrently and is now present: $targetDescription"
            } catch {
                $PSCmdlet.WriteError(
                    [System.Management.Automation.ErrorRecord]::new(
                        $_.Exception,
                        'AddRdpUserFailed',
                        [System.Management.Automation.ErrorCategory]::WriteError,
                        $id
                    )
                )
            }
        }
    }
}
