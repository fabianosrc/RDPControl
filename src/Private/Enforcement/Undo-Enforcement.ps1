<#
.SYNOPSIS
Restores the target binary to its original state from the latest
pre-enforcement snapshot.

.DESCRIPTION
Locates the most recent non-enforced snapshot stored in the database,
restores the original binary content, and validates the operation via
post-restore SHA256 hash verification.

Workflow:
    1. Validates elevation and target binary existence
    2. Acquires global enforcement mutex
    3. Locates the latest non-enforced snapshot
    4. Stops TermService if currently running
    5. Grants temporary write access to the binary
    6. Restores the original binary blob
    7. Restores original ACL and service state
    8. Validates restored hash against snapshot hash
    9. Records audit metadata

.EXAMPLE
PS C:\> Undo-Enforcement

.OUTPUTS
PSCustomObject
#>
function Undo-Enforcement {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param ()

    process {
        $targetBinary = 'termsrv.dll'
        $targetPath   = Join-Path -Path $env:SystemRoot -ChildPath "System32\$targetBinary"
        $mutexName    = 'Global\RDPControl'
        $mutex        = $null
        $mutexOwned   = $false

        try {
            if (-not (Test-IsElevated)) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.Security.SecurityException]::new(
                        'Administrative privileges are required.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $targetPath
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

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

            if (-not $PSCmdlet.ShouldProcess($targetPath, 'Restore original binary')) {
                return
            }

            $mutex = [System.Threading.Mutex]::new($false, $mutexName)

            try {
                $mutexOwned = $mutex.WaitOne(30000)
            } catch [System.Threading.AbandonedMutexException] {
                $mutexOwned = $true

                Write-Warning -Message (
                    'Recovered abandoned enforcement mutex. ' +
                    'Previous operation may have terminated unexpectedly.'
                )
            }

            if (-not $mutexOwned) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.TimeoutException]::new(
                        'Could not acquire enforcement lock. ' +
                        'Another RDPControl operation may be in progress.'
                    ),
                    'MutexTimeout',
                    [System.Management.Automation.ErrorCategory]::ResourceBusy,
                    $mutexName
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            Write-Verbose -Message 'Enforcement lock acquired.'

            # Step 1 - locate latest pre-enforcement snapshot
            $snapshot = Get-StoreRecord -Snapshot -Enforced $false -Latest

            if ($null -eq $snapshot) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'No pre-enforcement snapshot was found. ' +
                        'Restore operation cannot continue.'
                    ),
                    'SnapshotNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $targetPath
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            Write-Verbose -Message (
                "Restore snapshot selected: ID=$($snapshot.id), " +
                "Version=$($snapshot.dll_version)"
            )

            # Step 2 - retrieve stored binary blob
            $blobRecord = Get-StoreRecord -Snapshot -Id $snapshot.id

            if ($null -eq $blobRecord -or $null -eq $blobRecord.blob) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'Snapshot blob data is missing or invalid.'
                    ),
                    'SnapshotBlobMissing',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $snapshot.id
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            [byte[]]$blob = $blobRecord.blob

            # Step 3 - preserve ACL and service state
            $originalAcl = Get-Acl -LiteralPath $targetPath
            $service     = Get-Service -Name 'TermService'
            $wasRunning  = $service.Status -eq 'Running'

            if ($wasRunning) {
                Stop-TermService
            }

            $restoreErrors = [System.Collections.Generic.List[string]]::new()

            try {
                Grant-ProtectedFileAccess -Path $targetPath

                [System.IO.File]::WriteAllBytes($targetPath, $blob)

                Write-Verbose -Message 'Original binary restored.'
            } finally {
                try {
                    Restore-FileAcl -Path $targetPath -Acl $originalAcl
                } catch {
                    $restoreErrors.Add("ACL restore failed: $($_.Exception.Message)")
                }

                try {
                    if ($wasRunning) {
                        Start-TermService
                    }
                } catch {
                    $restoreErrors.Add("Service restore failed: $($_.Exception.Message)")
                }

                if ($restoreErrors.Count -gt 0) {
                    throw [System.InvalidOperationException]::new(
                        'One or more restoration operations failed: ' +
                        ($restoreErrors -join '; ')
                    )
                }
            }

            # Step 4 - validate restored binary hash
            $restoredAssembly = Read-PEFile -Path $targetPath
            $restoredHash     = Get-BinaryHash -Bytes $restoredAssembly.Bytes

            if ($restoredHash -ne $snapshot.sha256) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'Post-restore validation failed. ' +
                        "Expected hash '$($snapshot.sha256)' but got '$restoredHash'."
                    ),
                    'RestoreValidationFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $targetPath
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            Write-Verbose -Message 'Post-restore validation passed.'

            # Step 5 - persist audit metadata
            $detailsParts = @(
                "SnapshotId=$($snapshot.id)"
                "Hash=$restoredHash"
            )

            New-StoreRecord -Audit -Operation 'Undo-Enforcement' -Details ($detailsParts -join ';') | Out-Null

            Write-Verbose -Message 'Enforcement reverted successfully.'

            return [pscustomobject]@{
                Success    = $true
                SnapshotId = $snapshot.id
                Hash       = $restoredHash
                RestoredAt = (Get-Date).ToUniversalTime().ToString('o')
            }
        } finally {
            if ($null -ne $mutex) {
                try {
                    if ($mutexOwned) {
                        $mutex.ReleaseMutex()

                        Write-Verbose -Message 'Enforcement lock released.'
                    }
                } finally {
                    $mutex.Dispose()
                }
            }
        }
    }
}
