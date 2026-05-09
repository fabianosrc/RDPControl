<#
.SYNOPSIS
Restores the original ACL on a file.

.DESCRIPTION
Applies a previously captured FileSecurity object back to the target file,
restoring ownership and access rules to their original state.

This is an atomic Engine primitive. The caller is responsible for supplying
a valid FileSecurity object captured before modifications were made.

.PARAMETER Path
Full path to the target file.

.PARAMETER Acl
Previously captured FileSecurity object to restore.

.EXAMPLE
PS C:\> $originalAcl = Get-Acl -LiteralPath 'C:\Path\To\Example.dll'
PS C:\> # ... perform operations ...
PS C:\> Restore-FileAcl -Path 'C:\Path\To\Example.dll' -Acl $originalAcl

.INPUTS
None

.OUTPUTS
None
#>
function Restore-FileAcl {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Security.AccessControl.FileSecurity]$Acl
    )

    process {
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new(
                        'Target file was not found.',
                        $Path
                    ),
                    'RestoreAclFileNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Path
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            if ($PSCmdlet.ShouldProcess($Path, 'Restore original file ACL')) {
                Set-Acl -LiteralPath $Path -AclObject $Acl -ErrorAction Stop
                Write-Verbose -Message "Original ACL restored for: $Path"
            }
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'RestoreFileAclFailed',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $Path
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
