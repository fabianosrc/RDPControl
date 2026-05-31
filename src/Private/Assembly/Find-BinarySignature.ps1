<#
.SYNOPSIS
Locates and resolves a policy enforcement strategy within a PE byte array.

.DESCRIPTION
Scans a PE binary for known session policy check sequences and produces a
validated enforcement set that neutralises the policy enforcement logic.

Three independent scan strategies are used in order:

    Pass 1 - Standard (jz / jne, Windows 10 / Windows 11 up to 24H2):
        Scans for the 6-byte core pattern: 39 81 3C 06 00 00.
        Produces one enforcement record covering the core and branch.

    Pass 2 - REX convergence (jnz, Windows 11 25H2+):
        Scans for the 7-byte REX core: 41 39 81 3C 06 00 00.
        Collects all forward branches in the surrounding cluster region,
        detects a shared deny-path by branch target convergence (minimum
        ConvergenceThreshold branches required), and produces one neutralisation
        record per converging branch.

        Additionally captures intermediate branches - those pointing to
        targets between the anchor and the deny target - which represent
        secondary denial paths discovered via Ghidra CFG analysis.

        Handles near (0F 84 / 0F 85), short (74 / 75) and unsigned
        conditional (76) branches.

    Pass 3 - Session limit (all builds where applicable):
        Scans independently for the QuerySessionLimit enforcement check:
        MOV EBX, EAX / CMP EAX, 0xD00A0013 / JNZ.
        Neutralises the check by zeroing EAX and EBX before redirecting
        control flow unconditionally to the success path.
        Discovered via Ghidra CFG analysis of CSessionArbitrationDesktop
        and CSessionArbitrationCacheMode (Windows 11 25H2 build 26100.8521).

        Pass 3 executes exactly once, after the primary pass resolves.

.PARAMETER Bytes
Byte array representing the PE content to analyse.

.EXAMPLE
PS C:\> $pe = Read-PEFile -Path "$env:SystemRoot\System32\termsrv.dll"
PS C:\> Find-BinarySignature -Bytes $pe.Bytes

.INPUTS
System.Byte[]

.OUTPUTS
System.Management.Automation.PSCustomObject

Returns an object with the following properties:

    Found              [bool]
    Strategy           [string]
    EnforcementCount   [int]
    Enforcements       [object[]]
    SignatureIndex     [int]
    SignatureOffset    [string]
    WriteIndex         [int]    Backward-compat: first enforcement offset
    WriteOffset        [string] Backward-compat: first enforcement offset hex
    BranchType         [string]
    ReplacementBytes   [byte[]] Backward-compat: first enforcement bytes
    ReplacementHex     [string] Backward-compat: first enforcement hex
    ContextBefore      [byte[]]
    ContextAfter       [byte[]]
    CurrentBytes       [byte[]]
    DiscardedMatches   [int]

Each Enforcements element contains:

    Offset           [int]
    OffsetHex        [string]
    OriginalBytes    [byte[]]
    ReplacementBytes [byte[]]
    ReplacementHex   [string]
    Strategy         [string]

.NOTES
This function performs read-only byte analysis.
It does not modify the source binary.
#>
function Find-BinarySignature {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Bytes
    )

    begin {
        #region Constants

        # Standard core: CMP dword ptr [rcx+0x63C], eax (6 bytes)
        [byte[]]$StandardCore = 0x39, 0x81, 0x3C, 0x06, 0x00, 0x00

        # REX-prefixed core: CMP dword ptr [r9+0x63C], eax (7 bytes)
        [byte[]]$RexCore = 0x41, 0x39, 0x81, 0x3C, 0x06, 0x00, 0x00

        # Context window appended after core for CurrentBytes property.
        [int]$AfterWindowSize = 6

        # Bytes before the REX anchor included in the branch collection window.
        [int]$ClusterScanBefore = 48

        # Bytes after the REX anchor included in the branch collection window.
        [int]$ClusterScanWindow = 128

        # Minimum number of branches converging to the same deny-path target
        # required for Pass 2 to accept the anchor as validated.
        # Higher values reduce false positive risk at negligible coverage cost.
        [int]$ConvergenceThreshold = 3

        #endregion

        #region Helper functions

        # Returns a forward-branch descriptor if the byte at Offset is a
        # recognised conditional branch opcode, or $null otherwise.
        # Only positive-displacement (forward) branches are returned.
        function Get-ForwardBranch {
            [CmdletBinding()]
            [OutputType([pscustomobject])]
            param (
                [Parameter()]
                [byte[]]$Data,

                [Parameter()]
                [int]$Offset
            )

            if ($Offset -ge ($Data.Length - 1)) {
                return $null
            }

            # Near conditional branch: 0F 84 (JZ) / 0F 85 (JNZ) - 6 bytes
            if ($Data[$Offset] -eq 0x0F) {
                if ($Offset -ge ($Data.Length - 6)) {
                    return $null
                }

                if ($Data[$Offset + 1] -notin @(0x84, 0x85)) {
                    return $null
                }

                [int]$rel32 = [System.BitConverter]::ToInt32($Data, $Offset + 2)
                if ($rel32 -le 0) {
                    return $null
                }

                [int]$target = $Offset + 6 + $rel32
                if ($target -le $Offset -or $target -ge $Data.Length) {
                    return $null
                }

                return [PSCustomObject]@{
                    Offset = $Offset
                    Target = $target
                    Size   = 6
                    Bytes  = [byte[]]@($Data[$Offset..($Offset + 5)])
                }
            }

            # Short conditional branches: 74 (JZ) / 75 (JNE) / 76 (JBE) - 2 bytes
            # JBE (76) guards the DAT_180122170 verbosity check in 25H2.
            if ($Data[$Offset] -in @(0x74, 0x75, 0x76)) {
                if ($Offset -ge ($Data.Length - 2)) {
                    return $null
                }

                [sbyte]$rel8 = [System.Convert]::ToSByte($Data[$Offset + 1])
                if ($rel8 -le 0) {
                    return $null
                }

                [int]$target = $Offset + 2 + $rel8
                if ($target -le $Offset -or $target -ge $Data.Length) {
                    return $null
                }

                return [PSCustomObject]@{
                    Offset = $Offset
                    Target = $target
                    Size   = 2
                    Bytes  = [byte[]]@($Data[$Offset], $Data[$Offset + 1])
                }
            }

            return $null
        }

        # Builds a neutralisation record that replaces a branch with NOPs.
        function New-BranchNeutralisation {
            [CmdletBinding()]
            [OutputType([pscustomobject])]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions',
                '',
                Justification = 'A factory function that creates an object in memory. It does not modify the system state.'
            )]
            param (
                [Parameter()]
                [pscustomobject]$Branch
            )

            [byte[]]$nops = [byte[]]::new($Branch.Size)
            for ([int]$n = 0; $n -lt $Branch.Size; $n++) {
                $nops[$n] = 0x90
            }

            return [PSCustomObject]@{
                Offset           = $Branch.Offset
                OffsetHex        = '0x{0:X8}' -f $Branch.Offset
                OriginalBytes    = $Branch.Bytes
                ReplacementBytes = $nops
                ReplacementHex   = [string]::Join(' ', ($nops | ForEach-Object { $_.ToString('X2') }))
                Target           = $Branch.Target
                TargetHex        = '0x{0:X8}' -f $Branch.Target
                Strategy         = 'BranchNeutralisation'
            }
        }

        # Locates the QuerySessionLimit session-count enforcement check and
        # produces an enforcement record that forces S_OK on all code paths.
        #
        # Detection pattern (9 bytes):
        #
        #   8B D8                 MOV EBX, EAX
        #   3D 13 00 0A D0        CMP EAX, 0xD00A0013
        #   0F 85 xx xx xx xx    JNZ -> deny path
        #
        # Replacement (13 bytes, in-place):
        #
        #   33 DB                 XOR EBX, EBX   ; force return value to S_OK
        #   31 C0                 XOR EAX, EAX   ; force EAX to S_OK
        #   90 90 90 90           NOP x4         ; structural padding
        #   E9 xx xx xx xx        JMP rel32      ; always redirect to success path
        #
        # The JMP displacement is preserved verbatim from the original JNZ
        # because both instructions are 6 bytes, so their next-instruction
        # offsets are identical and no adjustment is required.
        #
        # Discovered via Ghidra CFG analysis of:
        #   CSessionArbitrationDesktop::QuerySessionLimit
        #   CSessionArbitrationCacheMode::TryToCreateNewSession
        # Confirmed on Windows 11 25H2, termsrv.dll 10.0.26100.8521.
        function Find-SessionLimitEnforcement {
            [CmdletBinding()]
            [OutputType([pscustomobject])]
            param (
                [Parameter()]
                [byte[]]$Data
            )

            [byte[]]$detectionPattern = 0x8B, 0xD8, 0x3D, 0x13, 0x00, 0x0A, 0xD0, 0x0F, 0x85

            for ([int]$q = 0; $q -lt ($Data.Length - 13); $q++) {
                if ($Data[$q] -ne 0x8B) {
                    continue
                }

                [bool]$matched = $true
                for ([int]$p = 1; $p -lt $detectionPattern.Length; $p++) {
                    if ($Data[$q + $p] -ne $detectionPattern[$p]) {
                        $matched = $false
                        break
                    }
                }

                if (-not $matched) {
                    continue
                }

                # Validate displacement: must be positive and resolve within binary bounds.
                # The JMP next-instruction is at q+13 (same as JNZ), so rel32 is preserved.
                [int]$rel32     = [System.BitConverter]::ToInt32($Data, $q + 9)
                [int]$jmpTarget = $q + 13 + $rel32

                if ($rel32 -le 0 -or $jmpTarget -le $q -or $jmpTarget -ge $Data.Length) {
                    Write-Verbose -Message (
                        '[Pass3] Invalid displacement at 0x{0:X8} (rel32=0x{1:X8}, target=0x{2:X8}). Skipping.' -f
                        $q, $rel32, $jmpTarget
                    )
                    continue
                }

                [byte[]]$original = @(
                    $Data[$q],     $Data[$q + 1],  $Data[$q + 2],  $Data[$q + 3],
                    $Data[$q + 4], $Data[$q + 5],  $Data[$q + 6],  $Data[$q + 7],
                    $Data[$q + 8], $Data[$q + 9],  $Data[$q + 10], $Data[$q + 11],
                    $Data[$q + 12]
                )

                [byte[]]$replacement = @(
                    0x33, 0xDB,        # XOR EBX, EBX
                    0x31, 0xC0,        # XOR EAX, EAX
                    0x90, 0x90,        # NOP x2
                    0x90, 0x90,        # NOP x2
                    0xE9,              # JMP rel32
                    $Data[$q + 9],     # displacement byte 0 (preserved from JNZ)
                    $Data[$q + 10],    # displacement byte 1
                    $Data[$q + 11],    # displacement byte 2
                    $Data[$q + 12]     # displacement byte 3
                )

                return [PSCustomObject]@{
                    Offset           = $q
                    OffsetHex        = '0x{0:X8}' -f $q
                    OriginalBytes    = $original
                    ReplacementBytes = $replacement
                    ReplacementHex   = [string]::Join(' ', ($replacement | ForEach-Object { $_.ToString('X2') }))
                    Target           = $jmpTarget
                    TargetHex        = '0x{0:X8}' -f $jmpTarget
                    Strategy         = 'SessionLimitNeutralisation'
                }
            }

            return $null
        }

        # Returns $true if any two enforcement records write to overlapping byte ranges.
        function Test-EnforcementOverlap {
            [CmdletBinding()]
            [OutputType([bool])]
            param (
                [Parameter()]
                [object[]]$Enforcements
            )

            for ([int]$a = 0; $a -lt $Enforcements.Count; $a++) {
                [int]$aStart = $Enforcements[$a].Offset
                [int]$aEnd   = $aStart + $Enforcements[$a].ReplacementBytes.Length - 1

                for ([int]$b = $a + 1; $b -lt $Enforcements.Count; $b++) {
                    [int]$bStart = $Enforcements[$b].Offset
                    [int]$bEnd   = $bStart + $Enforcements[$b].ReplacementBytes.Length - 1

                    if ($aStart -le $bEnd -and $bStart -le $aEnd) {
                        return $true
                    }
                }
            }

            return $false
        }

        # Returns $true if any enforcement record writes beyond the binary bounds.
        # Validates that Offset + ReplacementBytes.Length does not exceed the
        # source binary length, providing a final guard against out-of-range writes
        # that could silently corrupt the binary.
        function Test-EnforcementBound {
            [CmdletBinding()]
            [OutputType([bool])]
            param (
                [Parameter()]
                [object[]]$Enforcements,

                [Parameter()]
                [int]$BinaryLength
            )

            foreach ($record in $Enforcements) {
                [int]$writeEnd = $record.Offset + $record.ReplacementBytes.Length
                if ($record.Offset -lt 0 -or $writeEnd -gt $BinaryLength) {
                    return $true
                }
            }

            return $false
        }

        # Resolves the dominant deny-path group from a branch target map.
        # Selects the group with the highest branch count that meets the
        # convergence threshold, eliminating dependence on hashtable iteration
        # order and always preferring the structurally dominant deny-path.
        function Resolve-DenyPathGroup {
            [CmdletBinding()]
            [OutputType([pscustomobject])]
            param (
                [Parameter()]
                [hashtable]$TargetMap,

                [Parameter()]
                [int]$Threshold
            )

            # Primary sort: highest branch count (dominant deny-path).
            # Tie-breaker: lowest target offset (structurally closest to anchor).
            # Both criteria are stable and deterministic regardless of hashtable
            # enumeration order, which is unspecified in PowerShell 5.1.
            $bestEntry = $TargetMap.GetEnumerator() |
                Where-Object { $_.Value.Count -ge $Threshold } |
                Sort-Object -Property @(
                    @{
                        Expression = { $_.Value.Count }
                        Descending = $true
                    },
                    @{
                        Expression = { [int]$_.Key }
                        Descending = $false
                    }
                ) | Select-Object -First 1

            if ($null -eq $bestEntry) {
                return $null
            }

            return [PSCustomObject]@{
                Target = [int]$bestEntry.Key
                Group  = $bestEntry.Value
            }
        }

        #endregion
    }

    end {
        try {
            # Explicit initialisation required for StrictMode -Version Latest compatibility.
            $primaryResult          = $null
            $primaryEnforcementList = $null

            [int]$minimumSize = 7 + 7 + $AfterWindowSize

            if ($Bytes.Length -lt $minimumSize) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.IO.InvalidDataException]::new(
                            'The provided byte array is too small for signature analysis.'
                        ),
                        'BinaryTooSmall',
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        $Bytes
                    )
                )
            }

            [int]$discardedMatches = 0

            Write-Verbose -Message ("Searching {0} bytes for binary signature..." -f $Bytes.Length)

            #region Pass 1 - Standard core pattern

            # Handles jz (Windows 10) and jne (Windows 11 up to 24H2).
            # Core pattern: CMP dword ptr [rcx+0x63C], eax -> 39 81 3C 06 00 00

            [int]$coreSize         = $StandardCore.Length
            [int]$beforeWindowSize = 6
            [int]$searchLimit      = $Bytes.Length - $coreSize - $AfterWindowSize
            [int]$i                = $beforeWindowSize
            [byte]$firstByte       = $StandardCore[0]
            [byte]$secondByte      = $StandardCore[1]

            while ($i -le $searchLimit) {
                $i = [array]::IndexOf($Bytes, $firstByte, $i, ($searchLimit - $i + 1))

                if ($i -lt 0) {
                    break
                }

                if ($Bytes[$i + 1] -ne $secondByte) {
                    $i++
                    continue
                }

                $seqParams = @{
                    Source   = $Bytes
                    Offset   = $i
                    Expected = $StandardCore
                }

                if (-not (Test-ByteSequence @seqParams)) {
                    $i++
                    continue
                }

                Write-Verbose -Message ('[Pass1] Candidate detected at offset 0x{0:X8}.' -f $i)

                $beforeParams      = @{ Bytes = $Bytes; ReferenceIndex = $i }
                $beforeInstruction = Get-BeforeInstruction @beforeParams

                if ($null -eq $beforeInstruction) {
                    Write-Verbose -Message '[Pass1] Context validation failed (preceding window). Discarding.'
                    $discardedMatches++
                    $i++
                    continue
                }

                $branchParams = @{
                    Bytes           = $Bytes
                    ReferenceIndex  = $i
                    ReferenceLength = $coreSize
                }

                [string]$branchType = Get-BranchType @branchParams

                if ($branchType -eq 'Unknown') {
                    Write-Verbose -Message '[Pass1] Context validation failed (following branch). Discarding.'
                    $discardedMatches++
                    $i++
                    continue
                }

                Write-Verbose -Message ('[Pass1] Branch type identified: {0}.' -f $branchType)

                $replacementParams = @{
                    ModRM        = $beforeInstruction.ModRM
                    Displacement = $beforeInstruction.Displacement
                    JumpType     = $branchType
                }

                [byte[]]$replacementBytes = New-ReplacementByte @replacementParams

                [int]$writeIndex = if ($branchType -eq 'jne') {
                    $i - $beforeWindowSize
                } else {
                    $i
                }

                $coreEnforcement = [PSCustomObject]@{
                    Offset           = $writeIndex
                    OffsetHex        = '0x{0:X8}' -f $writeIndex
                    OriginalBytes    = Get-ByteRange -Bytes $Bytes -Start $writeIndex -Length $replacementBytes.Length
                    ReplacementBytes = $replacementBytes
                    ReplacementHex   = [string]::Join(' ', ($replacementBytes | ForEach-Object { $_.ToString('X2') }))
                    Target           = $null
                    TargetHex        = $null
                    Strategy         = 'CoreReplacement'
                }

                $primaryEnforcementList = [System.Collections.Generic.List[object]]::new()
                $primaryEnforcementList.Add($coreEnforcement)

                $primaryResult = [PSCustomObject]@{
                    PSTypeName       = 'RDPControl.BinarySignature'
                    Found            = $true
                    Strategy         = 'CoreReplacement'
                    EnforcementCount = 0
                    Enforcements     = [object[]]@()
                    SignatureIndex   = $i
                    SignatureOffset  = '0x{0:X8}' -f $i
                    WriteIndex       = $writeIndex
                    WriteOffset      = '0x{0:X8}' -f $writeIndex
                    BranchType       = $branchType
                    ReplacementBytes = $replacementBytes
                    ReplacementHex   = $coreEnforcement.ReplacementHex
                    ContextBefore    = [byte[]](Get-ByteRange -Bytes $Bytes -Start ($i - $beforeWindowSize) -Length $beforeWindowSize)
                    ContextAfter     = [byte[]](Get-ByteRange -Bytes $Bytes -Start ($i + $coreSize) -Length $AfterWindowSize)
                    CurrentBytes     = [byte[]](Get-ByteRange -Bytes $Bytes -Start $i -Length ($coreSize + $AfterWindowSize))
                    DiscardedMatches = $discardedMatches
                }

                Write-Verbose -Message ('[Pass1] Enforcement set resolved. Count={0}.' -f $primaryEnforcementList.Count)
                break
            }

            #endregion

            #region Pass 2 - REX convergence + CFG-lite

            # Handles jnz (Windows 11 25H2+) via convergence analysis.
            #
            # Phase A: discovers all forward branches in the cluster window and
            #          identifies the dominant shared deny-path by target convergence.
            #          Requires at least ConvergenceThreshold branches.
            #          The dominant group (highest branch count) is always selected,
            #          eliminating dependence on hashtable iteration order.
            #
            # Phase B: captures intermediate branches - those pointing to targets
            #          between the anchor and the deny target - which represent
            #          secondary denial paths (e.g. JBE -> DAT check at 0x62CAA).

            if ($null -eq $primaryResult) {
                Write-Verbose -Message '[Pass2] Standard pattern not found. Scanning REX variant (convergence + CFG-lite)...'

                [int]$rexCoreSize = $RexCore.Length

                for ([int]$k = 7; $k -lt ($Bytes.Length - $rexCoreSize); $k++) {

                    # Inline full-sequence comparison - avoids Array.IndexOf on 0x41
                    # which appears very frequently in x64 code as a REX prefix.
                    if (
                        $Bytes[$k]     -ne 0x41 -or
                        $Bytes[$k + 1] -ne 0x39 -or
                        $Bytes[$k + 2] -ne 0x81 -or
                        $Bytes[$k + 3] -ne 0x3C -or
                        $Bytes[$k + 4] -ne 0x06 -or
                        $Bytes[$k + 5] -ne 0x00 -or
                        $Bytes[$k + 6] -ne 0x00
                    ) {
                        continue
                    }

                    Write-Verbose -Message ('[Pass2] REX anchor located at 0x{0:X8}.' -f $k)

                    [int]$scanStart = [Math]::Max(0, $k - $ClusterScanBefore)
                    [int]$scanEnd   = [Math]::Min($Bytes.Length - 6, $k + $ClusterScanWindow)
                    $allBranches    = [System.Collections.Generic.List[object]]::new()

                    for ([int]$b = $scanStart; $b -lt $scanEnd; $b++) {
                        $branch = Get-ForwardBranch -Data $Bytes -Offset $b
                        if ($null -ne $branch) {
                            $allBranches.Add($branch)
                            Write-Verbose -Message (
                                '[Pass2] Branch: 0x{0:X8} -> 0x{1:X8}' -f $branch.Offset, $branch.Target
                            )
                            $b += ($branch.Size - 1)
                        }
                    }

                    if ($allBranches.Count -lt $ConvergenceThreshold) {
                        Write-Verbose -Message (
                            '[Pass2] Insufficient branches ({0} found, {1} required). Discarding.' -f
                            $allBranches.Count, $ConvergenceThreshold
                        )
                        $discardedMatches++
                        continue
                    }

                    # Phase A: build target map and resolve the dominant deny-path group.
                    $targetMap = @{}
                    foreach ($branch in $allBranches) {
                        [string]$key = [string]$branch.Target
                        if (-not $targetMap.ContainsKey($key)) {
                            $targetMap[$key] = [System.Collections.Generic.List[object]]::new()
                        }

                        $targetMap[$key].Add($branch)
                    }

                    $denyResolution = Resolve-DenyPathGroup -TargetMap $targetMap -Threshold $ConvergenceThreshold

                    if ($null -eq $denyResolution) {
                        Write-Verbose -Message '[Pass2] No shared deny-path detected. Discarding.'
                        $discardedMatches++
                        continue
                    }

                    [int]$denyTarget = $denyResolution.Target
                    $denyGroup       = $denyResolution.Group

                    Write-Verbose -Message (
                        '[Pass2] Shared deny-path: 0x{0:X8} ({1} converging branches).' -f
                        $denyTarget, $denyGroup.Count
                    )

                    # Build enforcement set.
                    $enforcementSet   = [System.Collections.Generic.List[object]]::new()
                    $denyGroupOffsets = [System.Collections.Generic.HashSet[int]]::new()

                    # Phase A: one neutralisation record per converging branch.
                    foreach ($branch in $denyGroup) {
                        $enforcementSet.Add((New-BranchNeutralisation -Branch $branch))
                        $denyGroupOffsets.Add($branch.Offset) | Out-Null
                        Write-Verbose -Message (
                            '[Pass2] Enforcement target (convergence): 0x{0:X8} ({1} NOPs).' -f
                            $branch.Offset, $branch.Size
                        )
                    }

                    # Phase B: intermediate branches (CFG-lite).
                    foreach ($branch in $allBranches) {
                        if ($denyGroupOffsets.Contains($branch.Offset)) {
                            continue
                        }

                        if ($branch.Target -gt $k -and $branch.Target -lt $denyTarget) {
                            $enforcementSet.Add((New-BranchNeutralisation -Branch $branch))
                            Write-Verbose -Message (
                                '[Pass2] Enforcement target (CFG-lite intermediate): 0x{0:X8} -> 0x{1:X8} ({2} NOPs).' -f
                                $branch.Offset, $branch.Target, $branch.Size
                            )
                        }
                    }

                    $primaryEnforcementList = [System.Collections.Generic.List[object]]::new()
                    foreach ($record in ($enforcementSet | Sort-Object -Property Offset)) {
                        $primaryEnforcementList.Add($record)
                    }

                    $leadEnforcement = $primaryEnforcementList[0]

                    $primaryResult = [PSCustomObject]@{
                        PSTypeName       = 'RDPControl.BinarySignature'
                        Found            = $true
                        Strategy         = 'SharedDenyPathNeutralisation'
                        EnforcementCount = 0
                        Enforcements     = [object[]]@()
                        SignatureIndex   = $k
                        SignatureOffset  = '0x{0:X8}' -f $k
                        WriteIndex       = $leadEnforcement.Offset
                        WriteOffset      = $leadEnforcement.OffsetHex
                        BranchType       = 'jnz'
                        ReplacementBytes = $leadEnforcement.ReplacementBytes
                        ReplacementHex   = $leadEnforcement.ReplacementHex
                        ContextBefore    = [byte[]](Get-ByteRange -Bytes $Bytes -Start ($k - 7) -Length 7)
                        ContextAfter     = [byte[]](Get-ByteRange -Bytes $Bytes -Start ($k + $rexCoreSize) -Length $AfterWindowSize)
                        CurrentBytes     = [byte[]](Get-ByteRange -Bytes $Bytes -Start $k -Length ($rexCoreSize + $AfterWindowSize))
                        DiscardedMatches = $discardedMatches
                    }

                    Write-Verbose -Message ('[Pass2] Enforcement set resolved. Count={0}.' -f $primaryEnforcementList.Count)
                    break
                }
            }

            #endregion

            #region Pass 3 - Session limit enforcement

            # Runs exactly once, after the primary pass resolves.
            # Independent of which primary pass succeeded.

            if ($null -ne $primaryResult) {
                Write-Verbose -Message '[Pass3] Scanning for session limit enforcement...'
                $sessionLimitEnforcement = Find-SessionLimitEnforcement -Data $Bytes

                $allEnforcements = [System.Collections.Generic.List[object]]::new()
                foreach ($record in $primaryEnforcementList) {
                    $allEnforcements.Add($record)
                }

                if ($null -ne $sessionLimitEnforcement) {
                    $allEnforcements.Add($sessionLimitEnforcement)
                    Write-Verbose -Message (
                        '[Pass3] Session limit enforcement located at 0x{0:X8}.' -f
                        $sessionLimitEnforcement.Offset
                    )
                } else {
                    Write-Verbose -Message '[Pass3] Session limit pattern not found (not required for this build).'
                }

                [object[]]$enforcementArray = $allEnforcements.ToArray()

                if (Test-EnforcementOverlap -Enforcements $enforcementArray) {
                    $PSCmdlet.ThrowTerminatingError(
                        [System.Management.Automation.ErrorRecord]::new(
                            [System.InvalidOperationException]::new(
                                'Enforcement overlap detected. Aborting to prevent binary corruption.'
                            ),
                            'EnforcementOverlap',
                            [System.Management.Automation.ErrorCategory]::InvalidResult,
                            $enforcementArray
                        )
                    )
                }

                $boundsParams = @{
                    Enforcements = $enforcementArray
                    BinaryLength = $Bytes.Length
                }

                if (Test-EnforcementBound @boundsParams) {
                    $PSCmdlet.ThrowTerminatingError(
                        [System.Management.Automation.ErrorRecord]::new(
                            [System.InvalidOperationException]::new(
                                'Enforcement record exceeds binary bounds. Aborting to prevent binary corruption.'
                            ),
                            'EnforcementOutOfBounds',
                            [System.Management.Automation.ErrorCategory]::InvalidResult,
                            $enforcementArray
                        )
                    )
                }

                $primaryResult.EnforcementCount = $enforcementArray.Count
                $primaryResult.Enforcements     = $enforcementArray

                return $primaryResult
            }

            #endregion

            Write-Verbose -Message ('No validated signature identified. Discarded matches: {0}.' -f $discardedMatches)

            return [PSCustomObject]@{
                PSTypeName       = 'RDPControl.BinarySignature'
                Found            = $false
                Strategy         = $null
                EnforcementCount = 0
                Enforcements     = [object[]]@()
                SignatureIndex   = -1
                SignatureOffset  = $null
                WriteIndex       = -1
                WriteOffset      = $null
                BranchType       = $null
                ReplacementBytes = $null
                ReplacementHex   = $null
                ContextBefore    = $null
                ContextAfter     = $null
                CurrentBytes     = $null
                DiscardedMatches = $discardedMatches
            }

        } catch {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            throw
        }
    }
}
