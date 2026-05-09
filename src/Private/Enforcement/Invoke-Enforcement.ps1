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
        $targetBinary = 'termsrv.dll'
        $targetPath   = Join-Path -Path $env:SystemRoot -ChildPath "System32\$targetBinary"
        $mutexName  = 'Global\RDPControl'
        $mutex      = $null
        $mutexOwned = $false

        try {
            # Guard: elevation
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

            # Guard: target binary exists
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

            # ShouldProcess before acquiring any resource
            if (-not $PSCmdlet.ShouldProcess($targetPath, 'Apply enforcement policy')) {
                return
            }

            # Acquire enforcement mutex
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

            # Step 1 - read and validate binary
            $assembly = Read-PEFile -Path $targetPath

            Write-Verbose -Message (
                "Binary read: $($assembly.Bytes.Length) bytes, " +
                "architecture: $($assembly.Architecture)"
            )

            # Step 2 - mandatory pre-enforcement snapshot (failure aborts)
            $osVersion  = (Get-CimInstance -ClassName Win32_OperatingSystem).Version
            $binVersion = Get-BinaryVersion -Path $targetPath
            $preHash    = Get-BinaryHash -Bytes $assembly.Bytes

            try {
                $snapshotParams = @{
                    DllPath    = $targetPath
                    DllVersion = $binVersion
                    OsBuild    = $osVersion
                    Sha256     = $preHash
                    Blob       = $assembly.Bytes
                    Enforced   = $false
                }

                $snapshotId = New-StoreRecord -Snapshot @snapshotParams

                Write-Verbose -Message "Pre-enforcement snapshot saved. ID: $snapshotId"
            } catch {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        "Snapshot failed - enforcement aborted. $_"
                    ),
                    'SnapshotFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $targetPath
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            # Step 3 - locate binary signature
            $signature = Find-BinarySignature -Bytes $assembly.Bytes

            if (-not $signature.Found) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'Target instruction not found in binary. Enforcement aborted.'
                    ),
                    'SignatureNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $targetPath
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            Write-Verbose -Message (
                "Signature found at $($signature.SignatureOffset). " +
                "Branch type: $($signature.BranchType)"
            )

            # Step 4 - stop service, write bytes, restore state
            $originalAcl = Get-Acl -LiteralPath $targetPath
            $service     = Get-Service -Name 'TermService'
            $wasRunning  = $service.Status -eq 'Running'

            if ($wasRunning) {
                Stop-TermService
            }

            $restoreErrors = [System.Collections.Generic.List[string]]::new()

            try {
                Grant-ProtectedFileAccess -Path $targetPath

                Write-BinaryByte -Path $targetPath -Offset $signature.WriteIndex -Bytes $signature.ReplacementBytes

                Write-Verbose -Message "Replacement bytes written at $($signature.WriteOffset)."
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

            # Step 5 - dual post-enforcement validation
            $enforcedAssembly = Read-PEFile -Path $targetPath
            $enforcedHash     = Get-BinaryHash -Bytes $enforcedAssembly.Bytes
            $postSignature    = Find-BinarySignature -Bytes $enforcedAssembly.Bytes

            if ($postSignature.Found) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'Post-enforcement validation failed - original signature still present.'
                    ),
                    'ValidationFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $targetPath
                )

                $PSCmdlet.ThrowTerminatingError($err)
            }

            Write-Verbose -Message 'Post-enforcement validation passed.'

            # Step 6 - persist enforced snapshot and audit record
            $snapshotParams = @{
                DllPath    = $targetPath
                DllVersion = $binVersion
                OsBuild    = $osVersion
                Sha256     = $enforcedHash
                Blob       = $enforcedAssembly.Bytes
                Enforced   = $true
            }

            New-StoreRecord -Snapshot @snapshotParams | Out-Null

            $detailsParts = @(
                "WriteOffset=$($signature.WriteOffset)"
                "BranchType=$($signature.BranchType)"
                "Hash=$enforcedHash"
            )

            $auditParams = @{
                Operation = 'Invoke-Enforcement'
                Details   = $detailsParts -join ';'
            }

            New-StoreRecord -Audit @auditParams | Out-Null

            Write-Verbose -Message 'Enforcement completed successfully.'

            return [pscustomobject]@{
                Success     = $true
                SnapshotId  = $snapshotId
                WriteOffset = $signature.WriteOffset
                Hash        = $enforcedHash
                EnforcedAt  = (Get-Date).ToUniversalTime().ToString('o')
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
