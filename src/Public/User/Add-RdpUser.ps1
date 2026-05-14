<#
.SYNOPSIS
Adds users or groups to the Remote Desktop Users local group.

.DESCRIPTION
Adds one or more local or domain accounts to the 'Remote Desktop Users'
local group. Skips accounts that are already members.

Accepts array input and pipeline input.

.PARAMETER Identity
One or more account names to add. Accepts 'Username' or 'DOMAIN\Username' format.

.EXAMPLE
PS C:\> Add-RdpUser -Identity 'User1'

.EXAMPLE
PS C:\> Add-RdpUser -Identity 'User1', 'DOMAIN\User2'

.EXAMPLE
PS C:\> 'User1', 'DOMAIN\User2' | Add-RdpUser

.INPUTS
System.String[]

.OUTPUTS
None
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
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.UnauthorizedAccessException]::new(
                    'Add-RdpUser requires elevated privileges. ' +
                    'Run PowerShell as Administrator.'
                ),
                'ElevationRequired',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }

        $existingMembers = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        Get-RdpUser | Select-Object -ExpandProperty Name | ForEach-Object {
            $shortName = ($_ -split '\\')[-1]
            [void]$existingMembers.Add($shortName)
        }
    }

    process {
        foreach ($id in $Identity) {
            # FIX #2: Normalize input to short name before every comparison.
            $shortId = ($id -split '\\')[-1]

            try {
                if ($existingMembers.Contains($shortId)) {
                    Write-Warning -Message "[$id] is already a member of Remote Desktop Users. Skipping."
                    continue
                }

                # FIX #3: Log when the user explicitly declines the confirmation prompt.
                if (-not $PSCmdlet.ShouldProcess($id, 'Add to Remote Desktop Users')) {
                    Write-Verbose -Message "[$id] skipped by user confirmation."
                    continue
                }

                Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $id -ErrorAction Stop

                # FIX #4: Update the in-memory set so a duplicate entry later in the
                #         same pipeline is caught and skipped rather than hitting an
                #         error from Add-LocalGroupMember.
                [void]$existingMembers.Add($shortId)

                # FIX #7: Build the audit details string directly - the intermediate
                #         array added no value.
                New-StoreAuditRecord -Operation 'Add-RdpUser' -Details "Identity=$id;Action=Added" | Out-Null

                Write-Verbose -Message "[$id] added to Remote Desktop Users."
            } catch {
                # FIX #5: Map the exception message to a more specific ErrorCategory
                #         instead of using the catch-all WriteError for every failure.
                $category = switch -Regex ($_.Exception.Message) {
                    'not found|no such|does not exist' {
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound
                        break
                    }
                    'access|permission|privilege|unauthorized' {
                        [System.Management.Automation.ErrorCategory]::PermissionDenied
                        break
                    }
                    default {
                        [System.Management.Automation.ErrorCategory]::WriteError
                    }
                }

                $err = [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'AddRdpUserFailed',
                    $category,
                    $id
                )

                $PSCmdlet.WriteError($err)
            }
        }
    }
}
