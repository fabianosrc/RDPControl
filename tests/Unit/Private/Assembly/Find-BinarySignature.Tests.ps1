Describe 'Find-BinarySignature' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Test-ByteSequence.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-ByteRange.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BeforeInstruction.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BranchType.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/New-ReplacementByte.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Find-BinarySignature.ps1"

        # Builds a minimal byte array containing a fully valid signature.
        # Layout: [padding] [BEFORE 6 bytes] [CORE 6 bytes] [AFTER 6 bytes] [padding]
        #
        #   BEFORE : 8B 81 38 06 00 00   (mov eax, [rcx+0x638])
        #   CORE   : 39 81 3C 06 00 00   (cmp [rcx+0x63C], eax)
        #   AFTER  : 0F 84 xx xx xx xx   (jz rel32) - default
        #            75 xx               (jne rel8) - Windows 11 24H2
        #
        function New-SignatureBlock {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions',
                '',
                Justification = 'Internal test helper.'
            )]
            param (
                [string]$BranchType = 'jz',
                [int]$PaddingBefore = 16,
                [int]$PaddingAfter  = 16,
                [byte]$ModRM        = 0x81
            )

            [System.Collections.Generic.List[byte]]$buffer = [System.Collections.Generic.List[byte]]::new()

            # Leading padding
            for ($i = 0; $i -lt $PaddingBefore; $i++) {
                $buffer.Add(0xCC)
            }

            # BEFORE instruction: mov r32, [rcx+0x638]
            $buffer.Add(0x8B)
            $buffer.Add($ModRM)
            $buffer.Add(0x38)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            # CORE pattern: cmp [rcx+0x63C], eax
            $buffer.Add(0x39)
            $buffer.Add(0x81)
            $buffer.Add(0x3C)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            # AFTER branch
            if ($BranchType -eq 'jz') {
                $buffer.Add(0x0F)
                $buffer.Add(0x84)
                $buffer.Add(0x10)
                $buffer.Add(0x00)
                $buffer.Add(0x00)
                $buffer.Add(0x00)
            } elseif ($BranchType -eq 'jne') {
                $buffer.Add(0x75)
                $buffer.Add(0x0A)

                # Pad remaining 4 bytes so AFTER window is still 6
                $buffer.Add(0x90)
                $buffer.Add(0x90)
                $buffer.Add(0x90)
                $buffer.Add(0x90)
            }

            # Trailing padding
            for ($i = 0; $i -lt $PaddingAfter; $i++) {
                $buffer.Add(0xCC)
            }

            return [byte[]]$buffer.ToArray()
        }
    }

    Context 'Signature found with jz branch (Windows 10 / Win11 up to 23H2)' {

        It 'Returns Found = $true for a valid jz signature' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.Found | Should -BeTrue
        }

        It 'Returns BranchType = jz' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.BranchType | Should -Be 'jz'
        }

        It 'Returns the correct SignatureIndex' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz' -PaddingBefore 16

            $result = Find-BinarySignature -Bytes $bytes

            # Core starts after 16 padding + 6 BEFORE = index 22
            $result.SignatureIndex | Should -Be 22
        }

        It 'Returns WriteIndex equal to SignatureIndex for jz' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.WriteIndex | Should -Be $result.SignatureIndex
        }

        It 'Returns non-empty ReplacementBytes' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.ReplacementBytes | Should -Not -BeNullOrEmpty
        }

        It 'Returns 12-byte ReplacementBytes for jz' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.ReplacementBytes | Should -HaveCount 12
        }
    }

    Context 'Signature found with jne branch (Windows 11 24H2+)' {

        It 'Returns Found = $true for a valid jne signature' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jne'

            $result = Find-BinarySignature -Bytes $bytes

            $result.Found | Should -BeTrue
        }

        It 'Returns BranchType = jne' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jne'

            $result = Find-BinarySignature -Bytes $bytes

            $result.BranchType | Should -Be 'jne'
        }

        It 'Returns WriteIndex = SignatureIndex - 6 for jne' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jne'

            $result = Find-BinarySignature -Bytes $bytes

            $result.WriteIndex | Should -Be ($result.SignatureIndex - 6)
        }

        It 'Returns 13-byte ReplacementBytes for jne' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jne'

            $result = Find-BinarySignature -Bytes $bytes

            $result.ReplacementBytes | Should -HaveCount 13
        }
    }

    Context 'Signature not found' {

        It 'Returns Found = $false when core pattern is absent' {
            [byte[]]$bytes = [byte[]]::new(128)

            $result = Find-BinarySignature -Bytes $bytes

            $result.Found | Should -BeFalse
        }

        It 'Returns SignatureIndex = -1 when not found' {
            [byte[]]$bytes = [byte[]]::new(128)

            $result = Find-BinarySignature -Bytes $bytes

            $result.SignatureIndex | Should -Be -1
        }

        It 'Returns $null for ReplacementBytes when not found' {
            [byte[]]$bytes = [byte[]]::new(128)

            $result = Find-BinarySignature -Bytes $bytes

            $result.ReplacementBytes | Should -BeNullOrEmpty
        }

        It 'Returns Found = $false when core pattern exists but BEFORE context is invalid' {
            [System.Collections.Generic.List[byte]]$buffer = [System.Collections.Generic.List[byte]]::new()

            # Padding (>= 6 bytes so search starts)
            for ($i = 0; $i -lt 16; $i++) { $buffer.Add(0xCC) }

            # Invalid BEFORE: wrong opcode (0x89 instead of 0x8B)
            $buffer.Add(0x89)
            $buffer.Add(0x81)
            $buffer.Add(0x38)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            # CORE pattern
            $buffer.Add(0x39)
            $buffer.Add(0x81)
            $buffer.Add(0x3C)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            # Valid AFTER (jz)
            $buffer.Add(0x0F)
            $buffer.Add(0x84)
            $buffer.Add(0x10)
            $buffer.Add(0x00)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            for ($i = 0; $i -lt 16; $i++) {
                $buffer.Add(0xCC)
            }

            $result = Find-BinarySignature -Bytes ([byte[]]$buffer.ToArray())

            $result.Found | Should -BeFalse
        }

        It 'Returns Found = $false when core pattern exists but AFTER branch is unknown' {
            [System.Collections.Generic.List[byte]]$buffer = [System.Collections.Generic.List[byte]]::new()

            for ($i = 0; $i -lt 16; $i++) {
                $buffer.Add(0xCC)
            }

            # Valid BEFORE
            $buffer.Add(0x8B)
            $buffer.Add(0x81)
            $buffer.Add(0x38)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            # CORE pattern
            $buffer.Add(0x39)
            $buffer.Add(0x81)
            $buffer.Add(0x3C)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            # Invalid AFTER: NOP instead of jz/jne
            $buffer.Add(0x90)
            $buffer.Add(0x90)
            $buffer.Add(0x90)
            $buffer.Add(0x90)
            $buffer.Add(0x90)
            $buffer.Add(0x90)

            for ($i = 0; $i -lt 16; $i++) {
                $buffer.Add(0xCC)
            }

            $result = Find-BinarySignature -Bytes ([byte[]]$buffer.ToArray())

            $result.Found | Should -BeFalse
        }
    }

    Context 'Discarded matches tracking' {

        It 'Counts discarded matches when BEFORE context fails' {
            [System.Collections.Generic.List[byte]]$buffer = [System.Collections.Generic.List[byte]]::new()

            for ($i = 0; $i -lt 16; $i++) {
                $buffer.Add(0xCC)
            }

            # First occurrence: invalid BEFORE
            $buffer.Add(0x89)
            $buffer.Add(0x81)
            $buffer.Add(0x38)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)
            $buffer.Add(0x39)
            $buffer.Add(0x81)
            $buffer.Add(0x3C)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)
            $buffer.Add(0x0F)
            $buffer.Add(0x84)
            $buffer.Add(0x10)
            $buffer.Add(0x00)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            for ($i = 0; $i -lt 16; $i++) {
                $buffer.Add(0xCC)
            }

            $result = Find-BinarySignature -Bytes ([byte[]]$buffer.ToArray())

            $result.DiscardedMatches | Should -BeGreaterOrEqual 1
        }

        It 'Returns DiscardedMatches = 0 when first match is valid' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.DiscardedMatches | Should -Be 0
        }
    }

    Context 'Output structure' {

        It 'Returns all expected properties when found' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $names = $result.PSObject.Properties.Name

            $names | Should -Contain 'Found'
            $names | Should -Contain 'SignatureIndex'
            $names | Should -Contain 'SignatureOffset'
            $names | Should -Contain 'WriteIndex'
            $names | Should -Contain 'WriteOffset'
            $names | Should -Contain 'BranchType'
            $names | Should -Contain 'ReplacementBytes'
            $names | Should -Contain 'ReplacementHex'
            $names | Should -Contain 'ContextBefore'
            $names | Should -Contain 'ContextAfter'
            $names | Should -Contain 'CurrentBytes'
            $names | Should -Contain 'DiscardedMatches'
        }

        It 'Returns SignatureOffset as a hex string' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.SignatureOffset | Should -Match '^0x[0-9A-F]{8}$'
        }

        It 'Returns ReplacementHex as space-separated hex string' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.ReplacementHex | Should -Match '^([0-9A-F]{2}\s)*[0-9A-F]{2}$'
        }

        It 'Has PSTypeName RDPControl.BinarySignature' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.PSTypeNames | Should -Contain 'RDPControl.BinarySignature'
        }

        It 'Returns all expected properties when not found' {
            [byte[]]$bytes = [byte[]]::new(128)

            $result = Find-BinarySignature -Bytes $bytes

            $names = $result.PSObject.Properties.Name

            $names | Should -Contain 'Found'
            $names | Should -Contain 'SignatureIndex'
            $names | Should -Contain 'DiscardedMatches'
        }
    }

    Context 'Context windows' {

        It 'Returns ContextBefore with 6 bytes from the BEFORE window' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.ContextBefore | Should -HaveCount 6
            $result.ContextBefore[0] | Should -Be 0x8B
        }

        It 'Returns ContextAfter with 6 bytes from the AFTER window' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.ContextAfter | Should -HaveCount 6
            $result.ContextAfter[0] | Should -Be 0x0F
            $result.ContextAfter[1] | Should -Be 0x84
        }

        It 'Returns CurrentBytes covering core + after (12 bytes)' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.CurrentBytes | Should -HaveCount 12
            $result.CurrentBytes[0] | Should -Be 0x39
            $result.CurrentBytes[1] | Should -Be 0x81
        }
    }

    Context 'Input validation' {

        It 'Throws when byte array is too small for signature analysis' {
            [byte[]]$tiny = 0x39, 0x81, 0x3C

            { Find-BinarySignature -Bytes $tiny } | Should -Throw
        }
    }

    Context 'Register variants' {

        It 'Finds signature with ModRM 0x91 (edx register)' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz' -ModRM 0x91

            $result = Find-BinarySignature -Bytes $bytes

            $result.Found | Should -BeTrue
        }
    }

    Context 'Multiple matches' {

        It 'Returns the first valid signature when multiple valid signatures exist' {
            [System.Collections.Generic.List[byte]]$buffer = [System.Collections.Generic.List[byte]]::new()

            # First valid signature
            [byte[]]$first = New-SignatureBlock -BranchType 'jz' -PaddingBefore 8 -PaddingAfter 8

            # Second valid signature
            [byte[]]$second = New-SignatureBlock -BranchType 'jne' -PaddingBefore 8 -PaddingAfter 8

            $buffer.AddRange($first)
            $buffer.AddRange([byte[]](0xCC, 0xCC, 0xCC, 0xCC))
            $buffer.AddRange($second)

            $result = Find-BinarySignature -Bytes ([byte[]]$buffer.ToArray())

            $result.Found | Should -BeTrue
            $result.BranchType | Should -Be 'jz'

            # First signature:
            # 8 padding + 6 BEFORE = 14
            $result.SignatureIndex | Should -Be 14
        }

        It 'Skips invalid matches and returns the next valid signature' {
            [System.Collections.Generic.List[byte]]$buffer = [System.Collections.Generic.List[byte]]::new()
            #
            # INVALID MATCH
            #
            for ($i = 0; $i -lt 16; $i++) {
                $buffer.Add(0xCC)
            }

            # Invalid BEFORE
            $buffer.Add(0x89)
            $buffer.Add(0x81)
            $buffer.Add(0x38)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            # CORE
            $buffer.Add(0x39)
            $buffer.Add(0x81)
            $buffer.Add(0x3C)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            # Valid AFTER
            $buffer.Add(0x0F)
            $buffer.Add(0x84)
            $buffer.Add(0x10)
            $buffer.Add(0x00)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            #
            # VALID MATCH
            #
            [byte[]]$valid = New-SignatureBlock -BranchType 'jne' -PaddingBefore 16

            $buffer.AddRange($valid)

            $result = Find-BinarySignature -Bytes ([byte[]]$buffer.ToArray())

            $result.Found | Should -BeTrue
            $result.BranchType | Should -Be 'jne'
            $result.DiscardedMatches | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Replacement byte validation' {

        It 'Returns a valid replacement patch for jz signatures' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $result.ReplacementBytes | Should -Not -BeNullOrEmpty
            $result.ReplacementBytes | Should -HaveCount 12

            # mov eax, 0x100
            $result.ReplacementBytes[0] | Should -Be 0xB8
        }

        It 'Returns a valid replacement patch for jne signatures' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jne'

            $result = Find-BinarySignature -Bytes $bytes

            $result.ReplacementBytes | Should -Not -BeNullOrEmpty
            $result.ReplacementBytes | Should -HaveCount 13

            # mov eax, 0x100
            $result.ReplacementBytes[0] | Should -Be 0xB8
        }
    }

    Context 'Offset consistency' {

        It 'Returns SignatureOffset matching SignatureIndex' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            $result = Find-BinarySignature -Bytes $bytes

            $expected = '0x{0:X8}' -f $result.SignatureIndex

            $result.SignatureOffset | Should -Be $expected
        }

        It 'Returns WriteOffset matching WriteIndex' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jne'

            $result = Find-BinarySignature -Bytes $bytes

            $expected = '0x{0:X8}' -f $result.WriteIndex

            $result.WriteOffset | Should -Be $expected
        }
    }

    Context 'Near-match rejection' {

        It 'Throws when signature contains unsupported ModRM encoding' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz' -ModRM 0xFF

            { Find-BinarySignature -Bytes $bytes } | Should -Throw 'Unsupported ModR/M encoding: 0xFF'
        }

        It 'Rejects signatures with truncated AFTER branch' {
            [System.Collections.Generic.List[byte]]$buffer = [System.Collections.Generic.List[byte]]::new()

            for ($i = 0; $i -lt 16; $i++) {
                $buffer.Add(0xCC)
            }

            # Valid BEFORE
            $buffer.Add(0x8B)
            $buffer.Add(0x81)
            $buffer.Add(0x38)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            # CORE
            $buffer.Add(0x39)
            $buffer.Add(0x81)
            $buffer.Add(0x3C)
            $buffer.Add(0x06)
            $buffer.Add(0x00)
            $buffer.Add(0x00)

            # Truncated jz
            $buffer.Add(0x0F)
            $buffer.Add(0x84)

            $result = Find-BinarySignature -Bytes ([byte[]]$buffer.ToArray())

            $result.Found | Should -BeFalse
        }

        It 'Rejects signatures with modified displacement bytes' {
            [byte[]]$bytes = New-SignatureBlock -BranchType 'jz'

            # Modify displacement in core instruction
            $bytes[25] = 0xFF

            $result = Find-BinarySignature -Bytes $bytes

            $result.Found | Should -BeFalse
        }
    }
}
