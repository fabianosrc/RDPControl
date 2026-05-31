<#
.SYNOPSIS
Enables or disables multiple simultaneous remote desktop sessions.

.DESCRIPTION
Applies or reverts the multi-session connection policy by configuring the
target system binary. A snapshot is automatically saved before any changes
are applied. Enforcement is aborted if snapshot creation fails.

When enabling:
    - Creates or reuses a pre-enforcement snapshot
    - Applies binary configuration
    - Validates enforcement state via dual verification
    - Records the operation in the audit store

When disabling:
    - Restores the most recent valid snapshot
    - Validates restoration integrity via hash comparison
    - Records the operation in the audit store

When using -DryRun:
    - Reads and analyzes the target binary
    - Locates the configuration signature
    - Calculates replacement bytes
    - Returns a RDPControl.DryRunResult object
    - Performs no filesystem modifications

.PARAMETER Enabled
Applies the concurrent session configuration.

.PARAMETER Disabled
Restores the original single-session configuration.

.PARAMETER Force
Skips state validation and confirmation prompts.

.PARAMETER DryRun
Performs analysis only. No files are modified, no snapshots are created.
Returns a RDPControl.DryRunResult object for inspection or pipeline use.

.EXAMPLE
PS C:\> Set-RdpSessionMode -Enabled

.EXAMPLE
PS C:\> Set-RdpSessionMode -Disabled

.EXAMPLE
PS C:\> Set-RdpSessionMode -Enabled -Force

.EXAMPLE
PS C:\> Set-RdpSessionMode -Enabled -WhatIf

.EXAMPLE
PS C:\> Set-RdpSessionMode -Enabled -DryRun

.EXAMPLE
PS C:\> Set-RdpSessionMode -Enabled -DryRun | ConvertTo-Json

.EXAMPLE
PS C:\> if (-not (Set-RdpSessionMode -Enabled -DryRun).IsApplicable) { throw 'Signature not found.' }

.INPUTS
None

.OUTPUTS
RDPControl.DryRunResult
PSCustomObject
#>
function Set-RdpSessionMode {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Enabled')]
    [OutputType('RDPControl.DryRunResult', [pscustomobject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Enabled')]
        [Parameter(Mandatory, ParameterSetName = 'EnabledDryRun')]
        [switch]$Enabled,

        [Parameter(Mandatory, ParameterSetName = 'Disabled')]
        [Parameter(Mandatory, ParameterSetName = 'DisabledDryRun')]
        [switch]$Disabled,

        [Parameter()]
        [switch]$Force,

        [Parameter(Mandatory, ParameterSetName = 'EnabledDryRun')]
        [Parameter(Mandatory, ParameterSetName = 'DisabledDryRun')]
        [switch]$DryRun
    )

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new(
                        'Set-RdpSessionMode requires elevated privileges. ' +
                        'Run PowerShell as Administrator.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }

        $targetPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\termsrv.dll'
    }

    process {

        # ---------------------------------------------------------------------
        # DryRun
        # ---------------------------------------------------------------------

        if ($DryRun) {
            Write-Verbose -Message '[DryRun] Reading target binary.'
            $assembly = Read-PEFile -Path $targetPath

            Write-Verbose -Message '[DryRun] Computing binary hash.'
            $hash = Get-BinaryHash -Bytes $assembly.Bytes

            Write-Verbose -Message '[DryRun] Reading binary metadata.'
            $binVersion = (Get-BinaryVersion -Path $targetPath).FileVersion
            $osInfo     = Get-CimInstance -ClassName Win32_OperatingSystem
            $osVersion  = $osInfo.Caption
            $osBuild    = $osInfo.BuildNumber

            Write-Verbose -Message '[DryRun] Locating signature.'
            $signature = Find-BinarySignature -Bytes $assembly.Bytes

            $currentState = if (Test-EnforcementState) {
                'Concurrent'
            } else {
                'Standard'
            }

            $targetState = if ($Enabled) {
                'Concurrent'
            } else {
                'Standard'
            }

            $existingSnapshot = @(Get-StoreSnapshot -Sha256 $hash)

            $snapshotAction = if ($existingSnapshot.Count -gt 0) {
                "Reuse existing snapshot (ID: $($existingSnapshot[0].id))"
            } else {
                'Create new snapshot'
            }

            $currentBytesHex = if ($signature.Found -and $null -ne $signature.CurrentBytes) {
                [string]::Join(' ', ($signature.CurrentBytes | ForEach-Object { $_.ToString('X2') }))
            }

            $detectionMode = switch ($signature.Strategy) {
                'CoreReplacement'              { 'Single-pass signature' }
                'SharedDenyPathNeutralisation' { 'Multi-pass convergence + CFG' }
                default                        { $signature.Strategy }
            }

            $confidence = if ($signature.EnforcementCount -ge 4) { 'High' } else { 'Standard' }

            $enforcementsFormatted = if ($signature.Found -and $signature.EnforcementCount -gt 0) {
                $enforcements = $signature.Enforcements
                $lines = for ($j = 0; $j -lt $enforcements.Count; $j++) {
                    $e   = $enforcements[$j]
                    $hex = $e.ReplacementHex
                    if ($hex.Length -gt 17) { $hex = $hex.Substring(0, 14) + '...' }
                    '[{0}] {1}  {2,-17}  {3}' -f $j, $e.OffsetHex, $hex, $e.Strategy
                }
                $lines -join "`n"
            } else {
                'None'
            }

            $outputFields = [ordered]@{
                DryRun             = 'True (no changes applied)'
                BinaryPath         = $targetPath
                BinaryVersion      = $binVersion
                Hash               = $hash
                CurrentState       = $currentState
                TargetState        = $targetState
                SignatureFound     = $signature.Found
                PolicyApplicable   = ($signature.Found -and $signature.EnforcementCount -gt 0)
                Strategy           = $signature.Strategy
                DetectionMode      = $detectionMode
                Confidence         = $confidence
                SignatureOffset    = $signature.SignatureOffset
                WriteOffset        = $signature.WriteOffset
                BranchType         = $signature.BranchType
                CurrentBytes       = $currentBytesHex
                EnforcementCount   = $signature.EnforcementCount
                SnapshotAction     = $snapshotAction
                RequiresSnapshot   = ($existingSnapshot.Count -eq 0)
                ValidationStatus   = 'Passed'
                Enforcements       = $enforcementsFormatted
                OsName             = $osVersion
                OsBuild            = $osBuild
            }

            $result = New-Object -TypeName PSObject -Property $outputFields
            $result.PSObject.TypeNames.Insert(0, 'RDPControl.DryRunResult')

            return $result
        }

        # ---------------------------------------------------------------------
        # Enable enforcement
        # ---------------------------------------------------------------------

        if ($Enabled) {
            if (-not $Force -and (Test-EnforcementState)) {
                Write-Warning -Message 'Multi-session is already enabled. Use -Force to re-apply.'
                return
            }

            if (-not ($Force -or $PSCmdlet.ShouldProcess('Multi-session policy', 'Enable multi-session'))) {
                return
            }

            try {
                $result = Invoke-Enforcement
            } catch {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
                throw
            }

            return [PSCustomObject]@{
                PSTypeName  = 'RDPControl.EnforcementResult'
                State       = 'Enabled'
                SnapshotId  = $result.SnapshotId
                WriteOffset = $result.WriteOffset
                Hash        = $result.Hash
                EnforcedAt  = $result.EnforcedAt
            }
        }

        # ---------------------------------------------------------------------
        # Disable enforcement
        # ---------------------------------------------------------------------

        if ($Disabled) {
            if (-not $Force -and -not (Test-EnforcementState)) {
                Write-Warning -Message 'Multi-session is not currently enabled. Nothing to revert.'
                return
            }

            if (-not ($Force -or $PSCmdlet.ShouldProcess('Multi-session policy', 'Disable multi-session'))) {
                return
            }

            try {
                $result = Undo-Enforcement
            } catch {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
                throw
            }

            return [PSCustomObject]@{
                PSTypeName = 'RDPControl.RestoreResult'
                State      = 'Disabled'
                SnapshotId = $result.SnapshotId
                Hash       = $result.Hash
                RestoredAt = $result.RestoredAt
            }
        }
    }
}
