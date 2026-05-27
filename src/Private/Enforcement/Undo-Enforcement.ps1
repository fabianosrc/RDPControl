<#
.SYNOPSIS
Restores the target binary to its original state from a snapshot.

.DESCRIPTION
Restores the original binary content using a previously stored snapshot
and validates the operation through post-restore integrity verification.

Workflow:
    1. Validates elevation and target binary existence
    2. Acquires the global enforcement mutex
    3. Resolves the requested or latest non-enforced snapshot
    4. Preserves current ACL and service state
    5. Stops TermService if currently running
    6. Grants temporary write access to the target binary
    7. Restores the original binary blob
    8. Restores ACL and service state
    9. Validates restored SHA256 integrity
    10. Persists audit metadata

.PARAMETER SnapshotId
Specifies the snapshot ID to restore.

When omitted, the latest non-enforced snapshot is restored.

.EXAMPLE
PS C:\> Undo-Enforcement

.EXAMPLE
PS C:\> Undo-Enforcement -SnapshotId 3

.OUTPUTS
PSCustomObject with properties:
    Success    [bool]   - whether restore succeeded
    SnapshotId [long]   - restored snapshot identifier
    Hash       [string] - SHA256 of restored binary
    RestoredAt [string] - ISO 8601 UTC timestamp
#>
function Undo-Enforcement {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$SnapshotId
    )

    process {
        $targetPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\termsrv.dll'
        $mutexName  = 'Global\RDPControl'

        $mutex      = $null
        $mutexOwned = $false

        $serviceWasRunning = $false
        $originalAcl       = $null

        try {
            # -----------------------------------------------------------------
            # Preconditions
            # -----------------------------------------------------------------

            if (-not (Test-IsElevated)) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Security.SecurityException]::new(
                            'Administrative privileges are required.'
                        ),
                        'ElevationRequired',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $targetPath
                    )
                )
            }

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

            if (-not $PSCmdlet.ShouldProcess($targetPath, 'Restore original binary')) {
                return
            }

            # -----------------------------------------------------------------
            # Concurrency Control
            # -----------------------------------------------------------------

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
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.TimeoutException]::new(
                            'Could not acquire enforcement lock. ' +
                            'Another RDPControl operation may already be running.'
                        ),
                        'MutexTimeout',
                        [System.Management.Automation.ErrorCategory]::ResourceBusy,
                        $mutexName
                    )
                )
            }

            Write-Verbose -Message 'Enforcement lock acquired.'

            # -----------------------------------------------------------------
            # Snapshot Resolution
            # -----------------------------------------------------------------

            $snapshotParams = if ($PSBoundParameters.ContainsKey('SnapshotId')) {
                @{
                    Id          = $SnapshotId
                    IncludeBlob = $true
                }
            } else {
                @{
                    Enforced    = $false
                    Latest      = $true
                    IncludeBlob = $true
                }
            }

            $snapshot = @(Get-StoreSnapshot @snapshotParams) | Select-Object -First 1

            if ($null -eq $snapshot) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            'No valid restore snapshot was found.'
                        ),
                        'SnapshotNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $targetPath
                    )
                )
            }

            if ($null -eq $snapshot.binary_blob) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            'Snapshot binary blob is missing or invalid.'
                        ),
                        'SnapshotBlobMissing',
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        $snapshot.id
                    )
                )
            }

            Write-Verbose -Message (
                "Restore snapshot selected. " +
                "Id=$($snapshot.id); " +
                "Version=$($snapshot.binary_version)"
            )

            [byte[]]$blob = $snapshot.binary_blob

            # -----------------------------------------------------------------
            # Preserve Current System State
            # -----------------------------------------------------------------

            $originalAcl = Get-Acl -LiteralPath $targetPath

            $service = Get-Service -Name 'TermService'
            $serviceWasRunning = $service.Status -eq 'Running'

            if ($serviceWasRunning) {
                Stop-TermService
            }

            # -----------------------------------------------------------------
            # Binary Restore
            # -----------------------------------------------------------------

            $writeException = $null

            try {
                Grant-ProtectedFileAccess -Path $targetPath

                $maxRetries = 3
                $retryDelay = 2

                for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
                    try {
                        Write-BinaryContent -Path $targetPath -Bytes $blob
                        break
                    } catch {
                        if ($attempt -eq $maxRetries) {
                            throw
                        }

                        Write-Verbose -Message (
                            "Binary file handle still locked. " +
                            "Retry $attempt/$maxRetries in ${retryDelay}s."
                        )

                        Start-Sleep -Seconds $retryDelay
                    }
                }

                Write-Verbose -Message 'Original binary restored successfully.'
            } catch {
                $writeException = $_
                throw
            } finally {
                $restoreFailures = [System.Collections.Generic.List[string]]::new()

                try {
                    if ($null -ne $originalAcl) {
                        Restore-FileAcl -Path $targetPath -Acl $originalAcl
                    }
                } catch {
                    $restoreFailures.Add("ACL restoration failed: $($_.Exception.Message)")
                }

                try {
                    if ($serviceWasRunning) {
                        Start-TermService
                    }
                } catch {
                    $restoreFailures.Add("Service restoration failed: $($_.Exception.Message)")
                }

                if ($restoreFailures.Count -gt 0) {
                    $restoreMessage = $restoreFailures -join '; '

                    if ($null -ne $writeException) {
                        throw [System.AggregateException]::new(
                            "Restore failed and state recovery was incomplete: $restoreMessage",
                            @($writeException.Exception)
                        )
                    }

                    throw [System.InvalidOperationException]::new(
                        "Restore completed, but state recovery was incomplete: $restoreMessage"
                    )
                }
            }

            # -----------------------------------------------------------------
            # Post-Restore Validation
            # -----------------------------------------------------------------

            $restoredAssembly = Read-PEFile -Path $targetPath

            $restoredHash = (Get-BinaryHash -Bytes $restoredAssembly.Bytes).Trim().ToLowerInvariant()

            $snapshotHash = ($snapshot.sha256).Trim().ToLowerInvariant()

            if ($restoredHash -ne $snapshotHash) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            'Post-restore validation failed. ' +
                            "Expected hash '$snapshotHash' but got '$restoredHash'."
                        ),
                        'RestoreValidationFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidResult,
                        $targetPath
                    )
                )
            }

            Write-Verbose -Message 'Post-restore validation succeeded.'

            # -----------------------------------------------------------------
            # Audit Metadata
            # -----------------------------------------------------------------

            $auditDetails = @{
                SnapshotId = $snapshot.id
                Hash       = $restoredHash
            } | ConvertTo-Json -Compress

            New-StoreAuditRecord -Operation 'Undo-Enforcement' -Details $auditDetails | Out-Null

            Write-Verbose -Message 'Enforcement reverted successfully.'

            [PSCustomObject]@{
                PSTypeName    = 'RDPControl.EnforcementUndoResult'
                Success       = $true
                SnapshotId    = $snapshot.id
                Hash          = $restoredHash
                RestoredAt    = (Get-Date).ToUniversalTime().ToString('o')
            }
        } catch {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $PSCmdlet.ThrowTerminatingError($_)
            }

            throw
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
