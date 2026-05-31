#Requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseShouldProcessForStateChangingFunctions',
    '',
    Justification = 'Pester test helpers'
)]
param ()

BeforeAll {
    Set-StrictMode -Version Latest

    $assemblyPath = Join-Path $PSScriptRoot '..\..\..\..\src\Private\Assembly'

    # Dot-source external dependencies first so Pester can mock them.
    . (Join-Path -Path $assemblyPath -ChildPath 'Get-ByteRange.ps1')
    . (Join-Path -Path $assemblyPath -ChildPath 'Test-ByteSequence.ps1')
    . (Join-Path -Path $assemblyPath -ChildPath 'Get-BeforeInstruction.ps1')
    . (Join-Path -Path $assemblyPath -ChildPath 'Get-BranchType.ps1')
    . (Join-Path -Path $assemblyPath -ChildPath 'New-ReplacementByte.ps1')

    # Dot-source the function under test.
    . (Join-Path -Path $assemblyPath -ChildPath 'Find-BinarySignature.ps1')

    #region Synthetic binary builders

    # Returns a PSCustomObject satisfying the Get-BeforeInstruction contract.
    function New-StubBeforeInstruction {
        return [PSCustomObject]@{
            ModRM        = [byte]0xC1
            Displacement = [byte[]]@(0x38, 0x06, 0x00, 0x00)
        }
    }

    # 30-byte binary with the standard core (39 81 3C 06 00 00) at offset 6.
    # beforeWindowSize = 6, so the scanner starts searching from i = 6.
    function New-Pass1TestByte {
        $bytes = [byte[]]::new(30)
        $bytes[6]  = 0x39; $bytes[7]  = 0x81; $bytes[8]  = 0x3C
        $bytes[9]  = 0x06; $bytes[10] = 0x00; $bytes[11] = 0x00

        return $bytes
    }

    # 30-byte binary that fully satisfies real validation without mocks:
    #   [00..05]: 8B 81 38 06 00 00  (MOV EAX, [rcx+0x638] - preceding instruction)
    #   [06..11]: 39 81 3C 06 00 00  (CMP [rcx+0x63C], eax - standard core)
    #   [12..13]: 75 01              (JNE rel8 = 1, target = 15 - branch)
    #   [14..29]: 00...
    # Used for Pass 1 integration tests that run with no mocks.
    function New-Pass1IntegrationByte {
        $bytes = [byte[]]::new(30)

        # Preceding instruction: 8B 81 38 06 00 00
        $bytes[0]  = 0x8B
        $bytes[1]  = 0x81
        $bytes[2]  = 0x38
        $bytes[3]  = 0x06
        $bytes[4]  = 0x00
        $bytes[5]  = 0x00

        # Standard core: 39 81 3C 06 00 00
        $bytes[6]  = 0x39
        $bytes[7]  = 0x81
        $bytes[8]  = 0x3C
        $bytes[9]  = 0x06
        $bytes[10] = 0x00
        $bytes[11] = 0x00

        # JNE rel8 = 1 → target = 15
        $bytes[12] = 0x75
        $bytes[13] = 0x01

        return $bytes
    }

    # 300-byte binary with:
    #   - REX core (41 39 81 3C 06 00 00) at offset 60
    #   - 3 near JNZ (0F 85) branches at offsets 15, 25, 35, all targeting 220
    #   - Optional CFG-lite JBE (76) at offset 70 targeting 150
    #     (60 < 150 < 220 qualifies as CFG-lite intermediate)
    #   - Optional QSL pattern at offset 160
    #     (rel32 = 77 → jmpTarget = 250, within bounds)
    function New-Pass2TestByte {
        param (
            [switch]$WithCfgLite,
            [switch]$WithQsl
        )

        $bytes = [byte[]]::new(300)

        # REX core at offset 60
        $bytes[60] = 0x41
        $bytes[61] = 0x39
        $bytes[62] = 0x81
        $bytes[63] = 0x3C
        $bytes[64] = 0x06
        $bytes[65] = 0x00
        $bytes[66] = 0x00

        # Branch 1 at 15 → 220: rel32 = 220 - (15+6) = 199 = 0xC7
        $bytes[15] = 0x0F
        $bytes[16] = 0x85
        $bytes[17] = 0xC7
        $bytes[18] = 0x00
        $bytes[19] = 0x00
        $bytes[20] = 0x00

        # Branch 2 at 25 → 220: rel32 = 220 - (25+6) = 189 = 0xBD
        $bytes[25] = 0x0F
        $bytes[26] = 0x85
        $bytes[27] = 0xBD
        $bytes[28] = 0x00
        $bytes[29] = 0x00
        $bytes[30] = 0x00

        # Branch 3 at 35 → 220: rel32 = 220 - (35+6) = 179 = 0xB3
        $bytes[35] = 0x0F
        $bytes[36] = 0x85
        $bytes[37] = 0xB3
        $bytes[38] = 0x00
        $bytes[39] = 0x00
        $bytes[40] = 0x00

        if ($WithCfgLite) {
            # JBE (76) at 70 → 150: rel8 = 150 - (70+2) = 78 = 0x4E
            $bytes[70] = 0x76
            $bytes[71] = 0x4E
        }

        if ($WithQsl) {
            # QSL at 160: 8B D8 3D 13 00 0A D0 0F 85 [rel32]
            # rel32 = 77 (0x4D) → jmpTarget = 160 + 13 + 77 = 250 < 300
            $bytes[160] = 0x8B
            $bytes[161] = 0xD8
            $bytes[162] = 0x3D
            $bytes[163] = 0x13
            $bytes[164] = 0x00
            $bytes[165] = 0x0A
            $bytes[166] = 0xD0
            $bytes[167] = 0x0F
            $bytes[168] = 0x85
            $bytes[169] = 0x4D
            $bytes[170] = 0x00
            $bytes[171] = 0x00
            $bytes[172] = 0x00
        }

        return $bytes
    }

    # 300-byte binary for short-branch convergence tests.
    # REX core at 60; 3 branches of a given opcode converging to target 95.
    # Exercises branch opcodes 74 (JZ), 75 (JNE), and mixed short+near.
    function New-ShortBranchTestByte {
        param (
            [Parameter(Mandatory)]
            [ValidateSet(0x74, 0x75)]
            [byte]$ShortOpcode
        )

        $bytes = [byte[]]::new(300)

        $bytes[60] = 0x41
        $bytes[61] = 0x39
        $bytes[62] = 0x81
        $bytes[63] = 0x3C
        $bytes[64] = 0x06
        $bytes[65] = 0x00
        $bytes[66] = 0x00

        # Short branch at 25 → 95: rel8 = 95 - (25+2) = 68 = 0x44
        $bytes[25] = $ShortOpcode
        $bytes[26] = 0x44

        # Short branch at 35 → 95: rel8 = 95 - (35+2) = 58 = 0x3A
        $bytes[35] = $ShortOpcode
        $bytes[36] = 0x3A

        # Near JNZ at 15 → 95: rel32 = 95 - (15+6) = 74 = 0x4A
        $bytes[15] = 0x0F
        $bytes[16] = 0x85
        $bytes[17] = 0x4A
        $bytes[18] = 0x00
        $bytes[19] = 0x00
        $bytes[20] = 0x00

        return $bytes
    }

    # 400-byte binary designed to trigger EnforcementOverlap.
    # The QSL pattern at offset 100 contains a near JNZ at bytes 107..112.
    # That inner JNZ is also detected as a convergence branch (→ target 190),
    # producing a NOP enforcement at 107..112 that overlaps with the QSL
    # enforcement at 100..112.
    #
    # Layout:
    #   REX core at 60
    #   Branch 1 at 15 → 190: near JNZ, rel32 = 190 - 21 = 169 = 0xA9
    #   Branch 2 at 25 → 190: near JNZ, rel32 = 190 - 31 = 159 = 0x9F
    #   QSL at 100: 8B D8 3D 13 00 0A D0 | 0F 85 4D 00 00 00
    #     → bytes 107..112 = 0F 85 4D 00 00 00 = near JNZ → target 190
    #     → QSL jmpTarget  = 100 + 13 + 77 = 190 (same target, no coincidence)
    #   Three branches to 190: at 15, 25, and 107 (the inner JNZ within QSL)
    #   Convergence group triggers NOP at 107 (size 6) → overlaps QSL at 100 (size 13)
    function New-OverlapTestByte {
        $bytes = [byte[]]::new(400)

        $bytes[60] = 0x41
        $bytes[61] = 0x39
        $bytes[62] = 0x81
        $bytes[63] = 0x3C
        $bytes[64] = 0x06
        $bytes[65] = 0x00
        $bytes[66] = 0x00

        # Branch 1 at 15 → 190: rel32 = 190 - 21 = 169 = 0xA9
        $bytes[15] = 0x0F
        $bytes[16] = 0x85
        $bytes[17] = 0xA9
        $bytes[18] = 0x00
        $bytes[19] = 0x00
        $bytes[20] = 0x00

        # Branch 2 at 25 → 190: rel32 = 190 - 31 = 159 = 0x9F
        $bytes[25] = 0x0F
        $bytes[26] = 0x85
        $bytes[27] = 0x9F
        $bytes[28] = 0x00
        $bytes[29] = 0x00
        $bytes[30] = 0x00

        # QSL at 100: 8B D8 3D 13 00 0A D0 | 0F 85 4D 00 00 00
        # Bytes 107..112 = 0F 85 4D 00 00 00 → near JNZ → target = 107+6+77 = 190
        # QSL jmpTarget  = 100+13+77 = 190
        $bytes[100] = 0x8B
        $bytes[101] = 0xD8
        $bytes[102] = 0x3D
        $bytes[103] = 0x13
        $bytes[104] = 0x00
        $bytes[105] = 0x0A
        $bytes[106] = 0xD0
        $bytes[107] = 0x0F
        $bytes[108] = 0x85
        $bytes[109] = 0x4D
        $bytes[110] = 0x00
        $bytes[111] = 0x00
        $bytes[112] = 0x00

        return $bytes
    }

    # 500-byte binary for tie-breaking:
    #   REX core at 60
    #   Target A = 200: 3 branches at offsets 12, 22, 32
    #   Target B = 350: 3 branches at offsets 80, 90, 100
    # Tie-breaker must select A (lower target offset, equal branch count).
    function New-TieBreakerTestByte {
        $bytes = [byte[]]::new(500)

        $bytes[60] = 0x41
        $bytes[61] = 0x39
        $bytes[62] = 0x81
        $bytes[63] = 0x3C
        $bytes[64] = 0x06
        $bytes[65] = 0x00
        $bytes[66] = 0x00

        # Branches to A = 200
        $bytes[12] = 0x0F
        $bytes[13] = 0x85  # rel32 = 200-18 = 182 = 0xB6
        $bytes[14] = 0xB6
        $bytes[15] = 0x00
        $bytes[16] = 0x00
        $bytes[17] = 0x00

        $bytes[22] = 0x0F
        $bytes[23] = 0x85  # rel32 = 200-28 = 172 = 0xAC
        $bytes[24] = 0xAC
        $bytes[25] = 0x00
        $bytes[26] = 0x00
        $bytes[27] = 0x00

        $bytes[32] = 0x0F
        $bytes[33] = 0x85  # rel32 = 200-38 = 162 = 0xA2
        $bytes[34] = 0xA2
        $bytes[35] = 0x00
        $bytes[36] = 0x00
        $bytes[37] = 0x00

        # Branches to B = 350
        $bytes[80] = 0x0F
        $bytes[81] = 0x85  # rel32 = 350-86 = 264 = 0x108
        $bytes[82] = 0x08
        $bytes[83] = 0x01
        $bytes[84] = 0x00
        $bytes[85] = 0x00

        $bytes[90] = 0x0F
        $bytes[91] = 0x85  # rel32 = 350-96 = 254 = 0xFE
        $bytes[92] = 0xFE
        $bytes[93] = 0x00
        $bytes[94] = 0x00
        $bytes[95] = 0x00

        $bytes[100] = 0x0F
        $bytes[101] = 0x85  # rel32 = 350-106 = 244 = 0xF4
        $bytes[102] = 0xF4
        $bytes[103] = 0x00
        $bytes[104] = 0x00
        $bytes[105] = 0x00

        return $bytes
    }

    #endregion
}

Describe 'Find-BinarySignature' {

    #region Context 1: Input validation
    Context 'Input validation' {

        It 'throws BinaryTooSmall when byte array is below minimum size' {
            { Find-BinarySignature -Bytes ([byte[]]@(0x00, 0x00, 0x00)) } |
                Should -Throw -ExceptionType ([System.IO.InvalidDataException])
        }

        It 'throws when byte array is empty' {
            { Find-BinarySignature -Bytes ([byte[]]@()) } | Should -Throw
        }

        It 'does not throw for a binary at exactly the minimum valid size (20 bytes)' {
            { Find-BinarySignature -Bytes ([byte[]]::new(20)) } | Should -Not -Throw
        }
    }
    #endregion

    #region Context 2: Pass 1 - No match
    Context 'Pass 1 - No match' {

        It 'returns Found=false when no standard core bytes exist in the binary' {
            $result = Find-BinarySignature -Bytes ([byte[]]::new(30))
            $result.Found            | Should -Be $false
            $result.DiscardedMatches | Should -Be 0
        }

        It 'skips candidate without incrementing DiscardedMatches when Test-ByteSequence returns false' {
            Mock Test-ByteSequence { return $false }

            $result = Find-BinarySignature -Bytes (New-Pass1TestByte)
            $result.Found            | Should -Be $false
            $result.DiscardedMatches | Should -Be 0
        }

        It 'discards and increments DiscardedMatches when Get-BeforeInstruction returns null' {
            Mock Test-ByteSequence     { return $true }
            Mock Get-BeforeInstruction { return $null }

            $result = Find-BinarySignature -Bytes (New-Pass1TestByte)
            $result.Found            | Should -Be $false
            $result.DiscardedMatches | Should -Be 1
        }

        It 'discards and increments DiscardedMatches when Get-BranchType returns Unknown' {
            Mock Test-ByteSequence     { return $true }
            Mock Get-BeforeInstruction { return (New-StubBeforeInstruction) }
            Mock Get-BranchType        { return 'Unknown' }

            $result = Find-BinarySignature -Bytes (New-Pass1TestByte)
            $result.Found            | Should -Be $false
            $result.DiscardedMatches | Should -Be 1
        }
    }
    #endregion

    #region Context 3: Pass 1 - Match (mocked)
    Context 'Pass 1 - Match (mocked helpers)' {

        BeforeEach {
            Mock Test-ByteSequence     { return $true }
            Mock Get-BeforeInstruction { return (New-StubBeforeInstruction) }
            Mock Get-BranchType        { return 'jz' }
            Mock New-ReplacementByte   { return [byte[]]@(0x90, 0x90, 0x90, 0x90, 0x90, 0x90) }
            Mock Get-ByteRange         { return [byte[]]::new($Length) }
        }

        It 'returns Found=true with Strategy CoreReplacement for a jz branch' {
            $result = Find-BinarySignature -Bytes (New-Pass1TestByte)
            $result.Found      | Should -Be $true
            $result.Strategy   | Should -Be 'CoreReplacement'
            $result.BranchType | Should -Be 'jz'
        }

        It 'sets WriteIndex equal to SignatureIndex for a jz branch' {
            $result = Find-BinarySignature -Bytes (New-Pass1TestByte)
            $result.WriteIndex | Should -Be $result.SignatureIndex
        }

        It 'sets WriteIndex to SignatureIndex minus 6 for a jne branch' {
            Mock Get-BranchType { return 'jne' }
            $result = Find-BinarySignature -Bytes (New-Pass1TestByte)
            $result.WriteIndex | Should -Be ($result.SignatureIndex - 6)
        }

        It 'produces exactly 1 enforcement when QSL pattern is absent' {
            $result = Find-BinarySignature -Bytes (New-Pass1TestByte)
            $result.EnforcementCount         | Should -Be 1
            $result.Enforcements             | Should -HaveCount 1
            $result.Enforcements[0].Strategy | Should -Be 'CoreReplacement'
        }

        It 'produces 2 enforcements when QSL pattern is present alongside Pass 1 match' {
            $bytes = [byte[]]::new(100)
            $bytes[6]  = 0x39
            $bytes[7]  = 0x81
            $bytes[8]  = 0x3C
            $bytes[9]  = 0x06
            $bytes[10] = 0x00
            $bytes[11] = 0x00

            # QSL at 50: rel32 = 30 → jmpTarget = 50+13+30 = 93 < 100
            $bytes[50] = 0x8B
            $bytes[51] = 0xD8
            $bytes[52] = 0x3D
            $bytes[53] = 0x13
            $bytes[54] = 0x00
            $bytes[55] = 0x0A
            $bytes[56] = 0xD0
            $bytes[57] = 0x0F
            $bytes[58] = 0x85
            $bytes[59] = 0x1E
            $bytes[60] = 0x00
            $bytes[61] = 0x00
            $bytes[62] = 0x00

            $result     = Find-BinarySignature -Bytes $bytes
            $strategies = $result.Enforcements | Select-Object -ExpandProperty Strategy

            $result.EnforcementCount | Should -Be 2
            $strategies | Should -Contain 'CoreReplacement'
            $strategies | Should -Contain 'SessionLimitNeutralisation'
        }

        It 'sets SignatureOffset as hex string of SignatureIndex' {
            $result = Find-BinarySignature -Bytes (New-Pass1TestByte)
            $result.SignatureOffset | Should -Be ('0x{0:X8}' -f $result.SignatureIndex)
        }

        It 'sets backward-compat WriteOffset as hex string of WriteIndex' {
            $result = Find-BinarySignature -Bytes (New-Pass1TestByte)
            $result.WriteOffset | Should -Be ('0x{0:X8}' -f $result.WriteIndex)
        }

        It 'sets backward-compat ReplacementBytes byte-for-byte equal to first enforcement bytes' {
            $result = Find-BinarySignature -Bytes (New-Pass1TestByte)
            $first  = $result.Enforcements[0].ReplacementBytes
            $result.ReplacementBytes.Length | Should -Be $first.Length
            for ($i = 0; $i -lt $first.Length; $i++) {
                $result.ReplacementBytes[$i] | Should -Be $first[$i]
            }
        }
    }
    #endregion

    #region Context 4: Pass 1 - Integration (no mocks)
    Context 'Pass 1 - Integration (real helpers, no mocks)' {

        It 'detects a real jne pattern and returns Found=true with correct strategy' {
            # Binary crafted to satisfy all real helper validations:
            #   [00..05]: 8B C1 38 06 00 00  (preceding MOV with anchor displacement)
            #   [06..11]: 39 81 3C 06 00 00  (standard core)
            #   [12..13]: 75 01              (JNE, target = 15)
            $result = Find-BinarySignature -Bytes (New-Pass1IntegrationByte)
            $result.Found      | Should -Be $true
            $result.Strategy   | Should -Be 'CoreReplacement'
            $result.BranchType | Should -Be 'jne'
        }

        It 'sets SignatureIndex to 6 (the core offset) in the real jne binary' {
            $result = Find-BinarySignature -Bytes (New-Pass1IntegrationByte)
            $result.SignatureIndex | Should -Be 6
        }

        It 'sets WriteIndex to 0 (SignatureIndex - 6) for a real jne branch' {
            $result = Find-BinarySignature -Bytes (New-Pass1IntegrationByte)
            $result.WriteIndex | Should -Be 0
        }
    }
    #endregion

    #region Context 5: Pass 2 - No match
    Context 'Pass 2 - No match' {

        It 'discards REX anchor and increments DiscardedMatches when fewer than 3 branches found' {
            $bytes = [byte[]]::new(300)
            $bytes[60] = 0x41
            $bytes[61] = 0x39
            $bytes[62] = 0x81
            $bytes[63] = 0x3C
            $bytes[64] = 0x06
            $bytes[65] = 0x00
            $bytes[66] = 0x00

            $bytes[15] = 0x0F
            $bytes[16] = 0x85
            $bytes[17] = 0xC7
            $bytes[18] = 0x00
            $bytes[19] = 0x00
            $bytes[20] = 0x00

            $bytes[25] = 0x0F
            $bytes[26] = 0x85
            $bytes[27] = 0xBD
            $bytes[28] = 0x00
            $bytes[29] = 0x00
            $bytes[30] = 0x00

            $result = Find-BinarySignature -Bytes $bytes
            $result.Found            | Should -Be $false
            $result.DiscardedMatches | Should -Be 2
        }

        It 'discards REX anchor when 3 branches have no shared target' {
            $bytes = [byte[]]::new(300)
            $bytes[60] = 0x41
            $bytes[61] = 0x39
            $bytes[62] = 0x81
            $bytes[63] = 0x3C
            $bytes[64] = 0x06
            $bytes[65] = 0x00
            $bytes[66] = 0x00

            $bytes[15] = 0x0F
            $bytes[16] = 0x85
            $bytes[17] = 0x81
            $bytes[18] = 0x00
            $bytes[19] = 0x00
            $bytes[20] = 0x00  # → 150

            $bytes[25] = 0x0F
            $bytes[26] = 0x85
            $bytes[27] = 0xA9
            $bytes[28] = 0x00
            $bytes[29] = 0x00
            $bytes[30] = 0x00  # → 200

            $bytes[35] = 0x0F
            $bytes[36] = 0x85
            $bytes[37] = 0xB3
            $bytes[38] = 0x00
            $bytes[39] = 0x00
            $bytes[40] = 0x00  # → 220

            $result = Find-BinarySignature -Bytes $bytes
            $result.Found            | Should -Be $false
            $result.DiscardedMatches | Should -Be 2
        }

        It 'discards REX anchor when best convergence group count is below threshold' {
            $bytes = [byte[]]::new(300)
            $bytes[60] = 0x41
            $bytes[61] = 0x39
            $bytes[62] = 0x81
            $bytes[63] = 0x3C
            $bytes[64] = 0x06
            $bytes[65] = 0x00
            $bytes[66] = 0x00

            $bytes[15] = 0x0F
            $bytes[16] = 0x85
            $bytes[17] = 0xC7
            $bytes[18] = 0x00
            $bytes[19] = 0x00
            $bytes[20] = 0x00  # → 220

            $bytes[25] = 0x0F
            $bytes[26] = 0x85
            $bytes[27] = 0xBD
            $bytes[28] = 0x00
            $bytes[29] = 0x00
            $bytes[30] = 0x00  # → 220

            $bytes[35] = 0x0F
            $bytes[36] = 0x85
            $bytes[37] = 0x81
            $bytes[38] = 0x00
            $bytes[39] = 0x00
            $bytes[40] = 0x00  # → 150

            $result = Find-BinarySignature -Bytes $bytes
            $result.Found            | Should -Be $false
            $result.DiscardedMatches | Should -Be 2
        }
    }
    #endregion

    #region Context 6: Pass 2 - Match
    Context 'Pass 2 - Match' {

        It 'returns Found=true with Strategy SharedDenyPathNeutralisation' {
            $result = Find-BinarySignature -Bytes (New-Pass2TestByte)
            $result.Found    | Should -Be $true
            $result.Strategy | Should -Be 'SharedDenyPathNeutralisation'
        }

        It 'sets BranchType to jnz' {
            $result = Find-BinarySignature -Bytes (New-Pass2TestByte)
            $result.BranchType | Should -Be 'jnz'
        }

        It 'produces exactly 3 enforcement records for 3 converging near JNZ branches' {
            $result = Find-BinarySignature -Bytes (New-Pass2TestByte)
            $result.EnforcementCount | Should -Be 3
            $result.Enforcements     | Should -HaveCount 3
        }

        It 'all convergence enforcements have Strategy BranchNeutralisation' {
            $result = Find-BinarySignature -Bytes (New-Pass2TestByte)
            foreach ($enforcement in $result.Enforcements) {
                $enforcement.Strategy | Should -Be 'BranchNeutralisation'
            }
        }

        It 'all convergence enforcements consist entirely of NOP bytes (0x90)' {
            $result = Find-BinarySignature -Bytes (New-Pass2TestByte)
            foreach ($enforcement in $result.Enforcements) {
                foreach ($byte in $enforcement.ReplacementBytes) {
                    $byte | Should -Be 0x90
                }
            }
        }

        It 'enforcements are sorted by Offset ascending' {
            $result  = Find-BinarySignature -Bytes (New-Pass2TestByte)
            $offsets = $result.Enforcements | Select-Object -ExpandProperty Offset
            $offsets | Should -Be ($offsets | Sort-Object)
        }

        It 'sets WriteIndex to the Offset of the first enforcement record' {
            $result = Find-BinarySignature -Bytes (New-Pass2TestByte)
            $result.WriteIndex | Should -Be $result.Enforcements[0].Offset
        }

        It 'produces 4 enforcement records when a CFG-lite JBE intermediate branch is detected' {
            $result = Find-BinarySignature -Bytes (New-Pass2TestByte -WithCfgLite)
            $result.EnforcementCount | Should -Be 4
        }

        It 'produces 4 enforcement records when QSL pattern is present' {
            $result     = Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)
            $strategies = $result.Enforcements | Select-Object -ExpandProperty Strategy

            $result.EnforcementCount | Should -Be 4
            $strategies              | Should -Contain 'SessionLimitNeutralisation'
        }

        It 'selects the dominant deny-path deterministically in a tie-breaking scenario' {
            # Targets A=200 and B=350 each have 3 branches. Lower offset wins → A.
            $result  = Find-BinarySignature -Bytes (New-TieBreakerTestByte)
            $offsets = $result.Enforcements | Select-Object -ExpandProperty Offset

            $result.Found            | Should -Be $true
            $result.EnforcementCount | Should -Be 3
            $offsets | Should -Contain 12
            $offsets | Should -Contain 22
            $offsets | Should -Contain 32
        }

        It 'detects convergence from short JNE (0x75) branches' {
            $result = Find-BinarySignature -Bytes (New-ShortBranchTestByte -ShortOpcode 0x75)
            $result.Found    | Should -Be $true
            $result.Strategy | Should -Be 'SharedDenyPathNeutralisation'
        }

        It 'detects convergence from short JZ (0x74) branches' {
            $result = Find-BinarySignature -Bytes (New-ShortBranchTestByte -ShortOpcode 0x74)
            $result.Found    | Should -Be $true
            $result.Strategy | Should -Be 'SharedDenyPathNeutralisation'
        }
    }
    #endregion

    #region Context 7: Pass 3 - Session limit enforcement
    Context 'Pass 3 - Session limit enforcement' {

        It 'does not include SessionLimitNeutralisation when QSL pattern is absent' {
            $strategies = (Find-BinarySignature -Bytes (New-Pass2TestByte)).Enforcements |
                Select-Object -ExpandProperty Strategy
            $strategies | Should -Not -Contain 'SessionLimitNeutralisation'
        }

        It 'includes SessionLimitNeutralisation when QSL pattern is present and valid' {
            $strategies = (Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)).Enforcements |
                Select-Object -ExpandProperty Strategy
            $strategies | Should -Contain 'SessionLimitNeutralisation'
        }

        It 'skips QSL when displacement rel32 is zero' {
            $bytes = New-Pass2TestByte
            $bytes[160] = 0x8B; $bytes[161] = 0xD8
            $bytes[162] = 0x3D; $bytes[163] = 0x13; $bytes[164] = 0x00
            $bytes[165] = 0x0A; $bytes[166] = 0xD0
            $bytes[167] = 0x0F; $bytes[168] = 0x85
            $bytes[169] = 0x00; $bytes[170] = 0x00; $bytes[171] = 0x00; $bytes[172] = 0x00  # rel32 = 0

            $strategies = (Find-BinarySignature -Bytes $bytes).Enforcements |
                Select-Object -ExpandProperty Strategy
            $strategies | Should -Not -Contain 'SessionLimitNeutralisation'
        }

        It 'skips QSL when jmpTarget equals BinaryLength (exact out-of-bounds)' {
            # BinaryLength = 300; jmpTarget = q+13+rel32 = 160+13+127 = 300 = BinaryLength → invalid
            $bytes = New-Pass2TestByte
            $bytes[160] = 0x8B; $bytes[161] = 0xD8
            $bytes[162] = 0x3D; $bytes[163] = 0x13; $bytes[164] = 0x00
            $bytes[165] = 0x0A; $bytes[166] = 0xD0
            $bytes[167] = 0x0F; $bytes[168] = 0x85
            $bytes[169] = 0x7F; $bytes[170] = 0x00; $bytes[171] = 0x00; $bytes[172] = 0x00  # rel32 = 127

            $strategies = (Find-BinarySignature -Bytes $bytes).Enforcements |
                Select-Object -ExpandProperty Strategy
            $strategies | Should -Not -Contain 'SessionLimitNeutralisation'
        }

        It 'QSL replacement byte 0 is 0x33 (XOR EBX opcode)' {
            $qsl = (Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)).Enforcements |
                Where-Object { $_.Strategy -eq 'SessionLimitNeutralisation' }
            $qsl.ReplacementBytes[0] | Should -Be 0x33
        }

        It 'QSL replacement byte 1 is 0xDB (XOR EBX operand)' {
            $qsl = (Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)).Enforcements |
                Where-Object { $_.Strategy -eq 'SessionLimitNeutralisation' }
            $qsl.ReplacementBytes[1] | Should -Be 0xDB
        }

        It 'QSL replacement byte 2 is 0x31 (XOR EAX opcode)' {
            $qsl = (Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)).Enforcements |
                Where-Object { $_.Strategy -eq 'SessionLimitNeutralisation' }
            $qsl.ReplacementBytes[2] | Should -Be 0x31
        }

        It 'QSL replacement byte 3 is 0xC0 (XOR EAX operand)' {
            $qsl = (Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)).Enforcements |
                Where-Object { $_.Strategy -eq 'SessionLimitNeutralisation' }
            $qsl.ReplacementBytes[3] | Should -Be 0xC0
        }

        It 'QSL replacement bytes 4-7 are NOP (0x90) padding' {
            $qsl = (Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)).Enforcements |
                Where-Object { $_.Strategy -eq 'SessionLimitNeutralisation' }
            $qsl.ReplacementBytes[4] | Should -Be 0x90
            $qsl.ReplacementBytes[5] | Should -Be 0x90
            $qsl.ReplacementBytes[6] | Should -Be 0x90
            $qsl.ReplacementBytes[7] | Should -Be 0x90
        }

        It 'QSL replacement byte 8 is 0xE9 (JMP rel32 opcode)' {
            $qsl = (Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)).Enforcements |
                Where-Object { $_.Strategy -eq 'SessionLimitNeutralisation' }
            $qsl.ReplacementBytes[8] | Should -Be 0xE9
        }

        It 'QSL preserves original JNZ displacement verbatim in JMP bytes 9-12' {
            # QSL at offset 160: original displacement at bytes 169..172 = 4D 00 00 00
            $qsl = (Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)).Enforcements |
                Where-Object { $_.Strategy -eq 'SessionLimitNeutralisation' }
            $qsl.ReplacementBytes[9]  | Should -Be 0x4D
            $qsl.ReplacementBytes[10] | Should -Be 0x00
            $qsl.ReplacementBytes[11] | Should -Be 0x00
            $qsl.ReplacementBytes[12] | Should -Be 0x00
        }

        It 'QSL replacement is exactly 13 bytes' {
            $qsl = (Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)).Enforcements |
                Where-Object { $_.Strategy -eq 'SessionLimitNeutralisation' }
            $qsl.ReplacementBytes.Length | Should -Be 13
        }

        It 'QSL Target resolves to the correct jmpTarget offset' {
            # jmpTarget = 160 + 13 + 77 = 250
            $qsl = (Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)).Enforcements |
                Where-Object { $_.Strategy -eq 'SessionLimitNeutralisation' }
            $qsl.Target    | Should -Be 250
            $qsl.TargetHex | Should -Be '0x000000FA'
        }
    }
    #endregion

    #region Context 8: Validation guards
    Context 'Validation - EnforcementOverlap' {

        It 'throws EnforcementOverlap when a convergence NOP and QSL enforcement overlap' {
            # New-OverlapTestByte produces a binary where:
            #   - Convergence branch at 107 → NOP enforcement covers 107..112
            #   - QSL at 100 → enforcement covers 100..112
            # Both are included in the result, causing a 107..112 overlap.
            { Find-BinarySignature -Bytes (New-OverlapTestByte) } |
                Should -Throw -ExceptionType ([System.InvalidOperationException])
        }
    }

    Context 'Validation - EnforcementBounds' {

        It 'all enforcement records produced by the scanner are always within binary bounds' {
            # Test-EnforcementBounds is a defense-in-depth guard.
            # The scanner mathematically cannot produce out-of-bounds enforcements
            # given its internal scan limits, so this validates the happy path:
            # no EnforcementOutOfBounds error is thrown for valid scanner output.
            $result = Find-BinarySignature -Bytes (New-Pass2TestByte -WithQsl)
            $result.Found | Should -Be $true

            foreach ($enforcement in $result.Enforcements) {
                $writeEnd = $enforcement.Offset + $enforcement.ReplacementBytes.Length
                $writeEnd | Should -BeLessOrEqual 300
            }
        }
    }
    #endregion

    #region Context 9: Output contract
    Context 'Output contract - Found=false' {

        BeforeEach {
            $Script:R = Find-BinarySignature -Bytes ([byte[]]::new(30))
        }

        It 'Found is false' {
            $Script:R.Found | Should -Be $false
        }

        It 'EnforcementCount is 0' {
            $Script:R.EnforcementCount | Should -Be 0
        }

        It 'Enforcements is empty' {
            $Script:R.Enforcements | Should -HaveCount 0
        }

        It 'Strategy is null' {
            $Script:R.Strategy | Should -BeNullOrEmpty
        }

        It 'SignatureIndex is -1' {
            $Script:R.SignatureIndex | Should -Be -1
        }

        It 'SignatureOffset is null' {
            $Script:R.SignatureOffset | Should -BeNullOrEmpty
        }

        It 'WriteIndex is -1' {
            $Script:R.WriteIndex | Should -Be -1
        }

        It 'WriteOffset is null' {
            $Script:R.WriteOffset | Should -BeNullOrEmpty
        }

        It 'BranchType is null' {
            $Script:R.BranchType | Should -BeNullOrEmpty
        }

        It 'ReplacementBytes is null' {
            $Script:R.ReplacementBytes | Should -BeNullOrEmpty
        }

        It 'ReplacementHex is null' {
            $Script:R.ReplacementHex | Should -BeNullOrEmpty
        }

        It 'PSTypeName is correct' {
            $Script:R.PSObject.TypeNames[0] |
                Should -Be 'RDPControl.BinarySignature'
        }

        It 'DiscardedMatches is present' {
            $Script:R.PSObject.Properties.Name |
                Should -Contain 'DiscardedMatches'
        }

    }

    Context 'Output contract - Found=true (Pass 1, mocked)' {

        BeforeEach {
            Mock Test-ByteSequence     { return $true }
            Mock Get-BeforeInstruction { return (New-StubBeforeInstruction) }
            Mock Get-BranchType        { return 'jz' }
            Mock New-ReplacementByte   { return [byte[]]@(0x90, 0x90, 0x90, 0x90, 0x90, 0x90) }
            Mock Get-ByteRange         { return [byte[]]::new($Length) }

            $Script:R = Find-BinarySignature -Bytes (New-Pass1TestByte)
        }

        It 'Found is true' {
            $Script:R.Found | Should -Be $true }

        It 'EnforcementCount is positive' {
            $Script:R.EnforcementCount | Should -BeGreaterThan 0
        }

        It 'Enforcements count matches EnforcementCount' {
            $Script:R.Enforcements.Count | Should -Be $Script:R.EnforcementCount
        }

        It 'WriteOffset is hex string of WriteIndex' {
            $Script:R.WriteOffset | Should -Be ('0x{0:X8}' -f $Script:R.WriteIndex)
        }

        It 'SignatureOffset is hex string of SignatureIndex'  {
            $Script:R.SignatureOffset | Should -Be ('0x{0:X8}' -f $Script:R.SignatureIndex)
        }

        It 'first enforcement has OffsetHex matching Offset' {
            $e = $Script:R.Enforcements[0]
            $e.OffsetHex | Should -Be ('0x{0:X8}' -f $e.Offset)
        }

        It 'first enforcement has OriginalBytes property' {
            $Script:R.Enforcements[0].PSObject.Properties.Name |
                Should -Contain 'OriginalBytes'
        }

        It 'PSTypeName is RDPControl.BinarySignature' {
            $Script:R.PSObject.TypeNames[0] |
                Should -Be 'RDPControl.BinarySignature'
        }
    }

    Context 'Output contract - Found=true (Pass 2, real scanner)' {

        BeforeEach {
            $Script:R = Find-BinarySignature -Bytes (New-Pass2TestByte)
        }

        It 'each enforcement has all required properties' {
            $required = @(
                'Offset'
                'OffsetHex'
                'OriginalBytes'
                'ReplacementBytes'
                'ReplacementHex'
                'Strategy'
            )

            foreach ($enforcement in $Script:R.Enforcements) {
                foreach ($prop in $required) {
                    $enforcement.PSObject.Properties.Name | Should -Contain $prop
                }
            }
        }

        It 'ContextBefore is a byte array' {
            $Script:R.ContextBefore.GetType() | Should -Be ([byte[]])
        }

        It 'ContextAfter is a byte array' {
            $Script:R.ContextAfter.GetType() | Should -Be ([byte[]])
        }

        It 'CurrentBytes is a byte array' {
            $Script:R.CurrentBytes.GetType() | Should -Be ([byte[]])
        }
    }
    #endregion

    #region Context 10: Idempotence
    Context 'Idempotence' {

        It 'returns Found=false after all convergence branches are neutralised with NOPs' {
            $bytes = New-Pass2TestByte

            for ($n = 15; $n -le 20; $n++) {
                $bytes[$n] = 0x90
            }

            for ($n = 25; $n -le 30; $n++) {
                $bytes[$n] = 0x90
            }

            for ($n = 35; $n -le 40; $n++) {
                $bytes[$n] = 0x90
            }


            (Find-BinarySignature -Bytes $bytes).Found | Should -Be $false
        }

        It 'returns Found=false after QSL enforcement bytes are written' {
            $bytes = New-Pass2TestByte -WithQsl

            for ($n = 15; $n -le 20; $n++) {
                $bytes[$n] = 0x90
            }

            for ($n = 25; $n -le 30; $n++) {
                $bytes[$n] = 0x90
            }

            for ($n = 35; $n -le 40; $n++) {
                $bytes[$n] = 0x90
            }

            # QSL enforcement: first 2 bytes change from 8B D8 to 33 DB
            $bytes[160] = 0x33
            $bytes[161] = 0xDB
            $bytes[162] = 0x31
            $bytes[163] = 0xC0
            $bytes[164] = 0x90
            $bytes[165] = 0x90
            $bytes[166] = 0x90
            $bytes[167] = 0x90
            $bytes[168] = 0xE9

            (Find-BinarySignature -Bytes $bytes).Found | Should -Be $false
        }
    }
    #endregion
}
