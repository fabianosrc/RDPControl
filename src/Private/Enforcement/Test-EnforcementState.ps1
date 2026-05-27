<#
.SYNOPSIS
Tests whether the current target binary matches the enforced state.

.DESCRIPTION
Computes the SHA256 hash of the current binary and compares it against
the most recent enforced snapshot stored in the database.

Returns $true if the current binary matches the enforced snapshot;
otherwise returns $false.

If no enforced snapshot exists, the function returns $false.

.EXAMPLE
PS C:\> Test-EnforcementState

.INPUTS
None

.OUTPUTS
System.Boolean
#>
function Test-EnforcementState {
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    process {
        $targetPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\termsrv.dll'

        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new(
                        'Target binary was not found.',
                        $targetPath
                    ),
                    'TargetBinaryNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $targetPath
                )
            )
        }

        $enforcedSnapshot = @(Get-StoreSnapshot -Enforced $true -Latest) | Select-Object -First 1

        if ($null -eq $enforcedSnapshot) {
            Write-Verbose -Message 'No enforced snapshot is available.'
            $false
            return
        }

        Write-Verbose -Message 'Computing current binary hash.'

        $assembly = Read-PEFile -Path $targetPath

        $currentHash = (Get-BinaryHash -Bytes $assembly.Bytes).Trim().ToLowerInvariant()

        if ([string]::IsNullOrWhiteSpace($enforcedSnapshot.sha256)) {
            Write-Verbose -Message 'Enforced snapshot has no valid hash.'
            $false
            return
        }

        $snapshotHash = ($enforcedSnapshot.sha256).Trim().ToLowerInvariant()

        $matchesEnforcedSnapshot = $currentHash -eq $snapshotHash

        Write-Verbose -Message "Current hash : $currentHash"
        Write-Verbose -Message "Snapshot hash: $snapshotHash"
        Write-Verbose -Message "State match  : $matchesEnforcedSnapshot"

        $matchesEnforcedSnapshot
    }
}
