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

.EXAMPLE
PS C:\> if (-not (Test-EnforcementState)) {
>>     Write-Warning 'Binary state differs from enforced snapshot.'
>> }

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
        try {
            $targetBinary = 'termsrv.dll'
            $targetPath   = Join-Path -Path $env:SystemRoot -ChildPath "System32\$targetBinary"

            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new(
                        'Target binary was not found.',
                        $targetPath
                    ),
                    'TargetBinaryNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $targetPath
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            $enforcedSnapshot = Get-StoreRecord -Snapshot -Enforced $true -Latest

            if ($null -eq $enforcedSnapshot) {
                Write-Verbose -Message 'No enforced snapshot found.'
                return $false
            }

            Write-Verbose -Message 'Computing current binary hash.'

            $assembly    = Read-PEFile -Path $targetPath
            $currentHash = Get-BinaryHash -Bytes $assembly.Bytes
            $isEnforced  = $currentHash -eq $enforcedSnapshot.sha256

            Write-Verbose -Message "Current hash : $currentHash"
            Write-Verbose -Message "Snapshot hash: $($enforcedSnapshot.sha256)"
            Write-Verbose -Message "State match  : $isEnforced"

            return $isEnforced
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestEnforcementStateFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $targetPath
            )

            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
