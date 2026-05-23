<#
.SYNOPSIS
Applies the connection policy by configuring the target binary.

.DESCRIPTION
Orchestrates the full enforcement workflow:
    1. Verifies administrative privileges
    2. Acquires a named mutex to prevent concurrent enforcement
    3. Reads and validates the current binary
    4. Saves a mandatory pre-enforcement snapshot (failure aborts)
    5. Stops TermService if running
    6. Grants write access to the binary
    7. Locates the target instruction via binary context validation
    8. Writes replacement bytes dynamically derived from binary context
    9. Restores original ACL and service state (guaranteed via finally)
    10. Validates enforcement via dual verification (hash + signature absence)
    11. Persists enforced snapshot and audit record

.EXAMPLE
PS C:\> Invoke-Enforcement

.OUTPUTS
PSCustomObject with properties:
    Success     [bool]   - whether enforcement was applied successfully
    SnapshotId  [long]   - ID of the pre-enforcement snapshot
    WriteOffset [string] - hex offset where bytes were written
    Hash        [string] - SHA256 of the enforced binary
    EnforcedAt  [string] - ISO 8601 UTC timestamp
#>
function Invoke-Enforcement {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param ()

    process {
        $targetPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\termsrv.dll'
        $mutexName  = 'Global\RDPControl'
        $mutex      = $null
        $mutexOwned = $false

        # Initialized outside try so finally can access them safely
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

            if (-not $PSCmdlet.ShouldProcess($targetPath, 'Apply enforcement policy')) {
                return
            }

            # -----------------------------------------------------------------
            # Concurrency control
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
                            'Another enforcement operation may already be running.'
                        ),
                        'MutexTimeout',
                        [System.Management.Automation.ErrorCategory]::ResourceBusy,
                        $mutexName
                    )
                )
            }

            Write-Verbose -Message 'Enforcement lock acquired.'

            # -----------------------------------------------------------------
            # Binary inspection
            # -----------------------------------------------------------------

            $assembly = Read-PEFile -Path $targetPath

            Write-Verbose -Message (
                "Binary loaded successfully. " +
                "Size=$($assembly.Bytes.Length) bytes; " +
                "Architecture=$($assembly.Architecture)"
            )

            $osVersion  = (Get-CimInstance -ClassName Win32_OperatingSystem).Version
            $binVersion = (Get-BinaryVersion -Path $targetPath).NormalizedVersion
            $preHash    = Get-BinaryHash -Bytes $assembly.Bytes

            # -----------------------------------------------------------------
            # Mandatory pre-enforcement snapshot
            # -----------------------------------------------------------------

            try {
                $snapshotParams = @{
                    BinaryPath    = $targetPath
                    BinaryVersion = $binVersion
                    OsBuild       = $osVersion
                    Sha256        = $preHash
                    BinaryBlob    = $assembly.Bytes
                    Enforced      = $false
                }

                $snapshotId = New-StoreSnapshot @snapshotParams

                Write-Verbose -Message "Pre-enforcement snapshot stored successfully. ID=$snapshotId"
            } catch {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            'Failed to create mandatory pre-enforcement snapshot.',
                            $_.Exception
                        ),
                        'SnapshotCreationFailed',
                        [System.Management.Automation.ErrorCategory]::WriteError,
                        $targetPath
                    )
                )
            }

            # -----------------------------------------------------------------
            # Signature resolution
            # -----------------------------------------------------------------

            $signature = Find-BinarySignature -Bytes $assembly.Bytes

            if (-not $signature.Found) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            'Target instruction signature was not found.'
                        ),
                        'SignatureNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $targetPath
                    )
                )
            }

            Write-Verbose -Message (
                "Signature located successfully. " +
                "Offset=$($signature.WriteOffset); " +
                "BranchType=$($signature.BranchType)"
            )

            # -----------------------------------------------------------------
            # Service and ACL state capture
            # -----------------------------------------------------------------

            $originalAcl       = Get-Acl -LiteralPath $targetPath
            $service           = Get-Service -Name 'TermService'
            $serviceWasRunning = $service.Status -eq 'Running'

            if ($serviceWasRunning) {
                Stop-TermService
            }

            # -----------------------------------------------------------------
            # Enforcement write
            # -----------------------------------------------------------------

            $writeException = $null

            try {
                Grant-ProtectedFileAccess -Path $targetPath

                $maxRetries = 3
                $retryDelay = 2

                for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
                    try {
                        $writeParams = @{
                            Path   = $targetPath
                            Offset = $signature.WriteIndex
                            Bytes  = $signature.ReplacementBytes
                        }

                        Write-BinaryByte @writeParams | Out-Null
                        break
                    } catch {
                        if ($attempt -eq $maxRetries) {
                            throw
                        }

                        Write-Verbose -Message (
                            "Binary handle still locked. " +
                            "Retry $attempt/$maxRetries in ${retryDelay}s."
                        )

                        Start-Sleep -Seconds $retryDelay
                    }
                }

                Write-Verbose -Message "Replacement bytes written successfully at offset $($signature.WriteOffset)."
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
                            "Enforcement failed and restoration was incomplete: $restoreMessage",
                            @($writeException.Exception)
                        )
                    }

                    throw [System.InvalidOperationException]::new(
                        "Enforcement completed but restoration was incomplete: $restoreMessage"
                    )
                }
            }

            # -----------------------------------------------------------------
            # Post-enforcement validation
            # -----------------------------------------------------------------

            $enforcedAssembly = Read-PEFile -Path $targetPath
            $enforcedHash     = Get-BinaryHash -Bytes $enforcedAssembly.Bytes
            $postSignature    = Find-BinarySignature -Bytes $enforcedAssembly.Bytes

            if ($postSignature.Found) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            'Post-enforcement validation failed. Original signature remains present.'
                        ),
                        'ValidationFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidResult,
                        $targetPath
                    )
                )
            }

            Write-Verbose -Message 'Post-enforcement validation succeeded.'

            # -----------------------------------------------------------------
            # Persist enforced snapshot and audit record
            # -----------------------------------------------------------------

            $enforcedSnapshotParams = @{
                BinaryPath    = $targetPath
                BinaryVersion = $binVersion
                OsBuild       = $osVersion
                Sha256        = $enforcedHash
                BinaryBlob    = $enforcedAssembly.Bytes
                Enforced      = $true
            }

            New-StoreSnapshot @enforcedSnapshotParams | Out-Null

            $auditDetails = [ordered]@{
                WriteOffset = $signature.WriteOffset
                BranchType  = $signature.BranchType
                Hash        = $enforcedHash
            } | ConvertTo-Json -Compress

            New-StoreAuditRecord -Operation 'Invoke-Enforcement' -Details $auditDetails | Out-Null

            Write-Verbose -Message 'Enforcement completed successfully.'

            return [PSCustomObject]@{
                Success     = $true
                SnapshotId  = $snapshotId
                WriteOffset = $signature.WriteOffset
                Hash        = $enforcedHash
                EnforcedAt  = (Get-Date).ToUniversalTime().ToString('o')
            }
        } catch {
            # Re-propagate ErrorRecords via ThrowTerminatingError to preserve
            # error ID and category. Unwrapped exceptions are re-thrown as-is.
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
