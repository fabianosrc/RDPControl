<#
.SYNOPSIS
Grants access permissions to a protected file.

.DESCRIPTION
Temporarily enables the required security privilege using a scoped privilege
object (RDPControl.PrivilegeScope) that deterministically restores the previous
privilege state on disposal, preventing privilege leakage into the host process.

Updates file ownership to the current user, grants file access permissions,
and optionally restores the original owner via a finally block.

This function is intended for internal engine use only.

.PARAMETER Path
Target file path.

.PARAMETER RestoreOwner
Restores the original file owner after access rules are applied.

.EXAMPLE
PS C:\> Grant-ProtectedFileAccess -Path 'C:\Path\To\Example.dll'

.EXAMPLE
PS C:\> Grant-ProtectedFileAccess -Path 'C:\Path\To\Example.dll' -RestoreOwner

.INPUTS
None

.OUTPUTS
None
#>
function Grant-ProtectedFileAccess {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [switch]$RestoreOwner
    )

    process {
        try {
            if (-not (Test-IsElevated)) {
                throw [System.Security.SecurityException]::new(
                    "Administrative privileges are required."
                )
            }

            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new("File not found.", $Path),
                    "ProtectedFileNotFound",
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Path
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath

            $privilegeScope = $null

            try {
                # Scoped privilege - automatically restores previous state on Dispose
                $privilegeScope = [RDPControl.PrivilegeScope]::new("SeTakeOwnershipPrivilege")

                Write-Verbose -Message "Retrieving current access control information."

                $acl = Get-Acl -LiteralPath $resolvedPath

                # Store as IdentityReference to avoid format issues on restore
                [System.Security.Principal.IdentityReference]$originalOwner = $acl.GetOwner(
                    [System.Security.Principal.SecurityIdentifier]
                )

                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User

                if ($null -eq $currentUser) {
                    throw [System.Security.SecurityException]::new(
                        "Unable to resolve current user identity."
                    )
                }

                try {
                    Write-Verbose -Message "Updating file ownership."

                    $acl.SetOwner($currentUser)
                    Set-Acl -LiteralPath $resolvedPath -AclObject $acl

                    # Re-read ACL after ownership change
                    $acl = Get-Acl -LiteralPath $resolvedPath

                    $accessRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                        $currentUser,
                        [System.Security.AccessControl.FileSystemRights]::FullControl,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )

                    Write-Verbose -Message "Applying file access rule."

                    $acl.SetAccessRule($accessRule)
                    Set-Acl -LiteralPath $resolvedPath -AclObject $acl

                    Write-Verbose -Message "Protected file access successfully updated."
                } finally {
                    if ($RestoreOwner -and $null -ne $originalOwner) {
                        Write-Verbose -Message "Restoring original file ownership."

                        $acl = Get-Acl -LiteralPath $resolvedPath
                        $acl.SetOwner($originalOwner)
                        Set-Acl -LiteralPath $resolvedPath -AclObject $acl
                    }
                }
            } finally {
                if ($null -ne $privilegeScope) {
                    $privilegeScope.Dispose()
                }
            }
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                "GrantProtectedFileAccessFailed",
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $Path
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
