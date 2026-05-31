Describe 'Invoke-Enforcement' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Test-ByteSequence.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-ByteRange.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BeforeInstruction.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BranchType.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/New-ReplacementByte.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BinaryHash.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BinaryVersion.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-PEArchitecture.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Read-PEFile.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Write-BinaryByte.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Find-BinarySignature.ps1"
        . "$PSScriptRoot/../../../../src/Private/Engine/Test-IsElevated.ps1"
        . "$PSScriptRoot/../../../../src/Private/Engine/Stop-TermService.ps1"
        . "$PSScriptRoot/../../../../src/Private/Engine/Start-TermService.ps1"
        . "$PSScriptRoot/../../../../src/Private/Engine/Grant-ProtectedFileAccess.ps1"
        . "$PSScriptRoot/../../../../src/Private/Engine/Restore-FileAcl.ps1"
        . "$PSScriptRoot/../../../../src/Private/Store/Core/New-StoreSnapshot.ps1"
        . "$PSScriptRoot/../../../../src/Private/Store/Core/New-StoreAuditRecord.ps1"
        . "$PSScriptRoot/../../../../src/Private/Enforcement/Invoke-Enforcement.ps1"

        $Script:MockPreHash = 'aaa111aaa111aaa111aaa111aaa111aaa111aaa111aaa111aaa111aaa111aaaa'

        $Script:MockEnforcedHash = 'bbb222bbb222bbb222bbb222bbb222bbb222bbb222bbb222bbb222bbb222bbbb'

        $Script:MockAssembly = [PSCustomObject]@{
            PSTypeName   = 'RDPControl.PEFile'
            Bytes        = [byte[]](0x4D, 0x5A, 0x00, 0x00)
            Architecture = 'x64'
            Path         = 'C:\Windows\System32\termsrv.dll'
        }

        $Script:MockSignatureFound = [PSCustomObject]@{
            PSTypeName       = 'RDPControl.BinarySignature'
            Found            = $true
            Strategy         = 'CoreReplacement'
            EnforcementCount = 1
            Enforcements     = @(
                [PSCustomObject]@{
                    Offset           = 100
                    OffsetHex        = '0x00000064'
                    ReplacementBytes = [byte[]](0xB8, 0x00, 0x01, 0x00, 0x00, 0x89, 0x81, 0x38, 0x06, 0x00, 0x00, 0x90)
                    ReplacementHex   = 'B8 00 01 00 00 89 81 38 06 00 00 90'
                    Strategy         = 'CoreReplacement'
                }
            )
            SignatureIndex   = 100
            SignatureOffset  = '0x00000064'
            WriteIndex       = 100
            WriteOffset      = '0x00000064'
            BranchType       = 'jz'
            ReplacementBytes = [byte[]](0xB8, 0x00, 0x01, 0x00, 0x00, 0x89, 0x81, 0x38, 0x06, 0x00, 0x00, 0x90)
            ReplacementHex   = 'B8 00 01 00 00 89 81 38 06 00 00 90'
            ContextBefore    = [byte[]](0x8B, 0x81, 0x38, 0x06, 0x00, 0x00)
            ContextAfter     = [byte[]](0x0F, 0x84, 0x10, 0x00, 0x00, 0x00)
            CurrentBytes     = [byte[]](0x39, 0x81, 0x3C, 0x06, 0x00, 0x00, 0x0F, 0x84, 0x10, 0x00, 0x00, 0x00)
            DiscardedMatches = 0
        }

        $Script:MockSignatureNotFound = [PSCustomObject]@{
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
            DiscardedMatches = 0
        }

        $Script:MockBinaryVersion = [PSCustomObject]@{
            PSTypeName        = 'RDPControl.BinaryVersion'
            Path              = 'C:\Windows\System32\termsrv.dll'
            FileVersion       = '10.0.19041.1'
            ProductVersion    = '10.0.19041.1'
            NormalizedVersion = [System.Version]'10.0.19041.1'
        }

        $Script:MockAcl = [System.Security.AccessControl.FileSecurity]::new()

        $Script:MockRunningService = [PSCustomObject]@{
            Name   = 'TermService'
            Status = 'Running'
        }

        $Script:MockStoppedService = [PSCustomObject]@{
            Name   = 'TermService'
            Status = 'Stopped'
        }

        function Initialize-DefaultEnforcementMock {
            param (
                [switch]$ServiceRunning,
                [switch]$PostValidationFails
            )

            $Script:PostValidationFailsEnabled = $PostValidationFails.IsPresent

            Mock Test-IsElevated { $true }

            Mock Test-Path { $true }

            Mock Read-PEFile { $Script:MockAssembly }

            Mock Get-CimInstance {
                [PSCustomObject]@{
                    Version = '10.0.19041'
                }
            }

            Mock Get-BinaryVersion { $Script:MockBinaryVersion }

            $Script:HashSequence = @($Script:MockPreHash, $Script:MockEnforcedHash)

            Mock Get-BinaryHash {
                $current = $Script:HashSequence[0]

                if ($Script:HashSequence.Count -gt 1) {
                    $Script:HashSequence = $Script:HashSequence[1..($Script:HashSequence.Count - 1)]
                }

                return $current
            }

            Mock New-StoreSnapshot { 1 }

            Mock New-StoreAuditRecord { 1 }

            Mock Get-Acl { $Script:MockAcl }

            Mock Grant-ProtectedFileAccess { }

            Mock Restore-FileAcl { }

            Mock Write-BinaryByte {
                [PSCustomObject]@{
                    Success = $true
                }
            }

            Mock Stop-TermService { }

            Mock Start-TermService { }

            if ($ServiceRunning) {
                Mock Get-Service { $Script:MockRunningService }
            } else {
                Mock Get-Service { $Script:MockStoppedService }
            }

            $Script:SignaturePhase = 'Pre'

            Mock Find-BinarySignature {
                if ($Script:SignaturePhase -eq 'Pre') {
                    $Script:SignaturePhase = 'Post'

                    return $Script:MockSignatureFound
                }

                if ($Script:PostValidationFailsEnabled) {
                    return $Script:MockSignatureFound
                }

                return $Script:MockSignatureNotFound
            }
        }
    }

    Context 'Successful enforcement' {

        BeforeAll {
            Initialize-DefaultEnforcementMock -ServiceRunning
        }

        BeforeEach {
            $Script:SignaturePhase = 'Pre'
            $Script:HashSequence   = @($Script:MockPreHash, $Script:MockEnforcedHash)
        }

        It 'Returns a successful enforcement result object' {
            $result = Invoke-Enforcement -Confirm:$false

            $result.Success | Should -BeTrue
            $result.SnapshotId | Should -Be 1
            $result.WriteOffset | Should -Be '0x00000064'
            $result.EnforcedAt | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }

        It 'Stops TermService before writing' {
            Invoke-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Stop-TermService -Times 1 -Exactly
        }

        It 'Grants protected file access before writing' {
            Invoke-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Grant-ProtectedFileAccess -Times 1 -Exactly
        }

        It 'Writes replacement bytes exactly once' {
            Invoke-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Write-BinaryByte -Times 1 -Exactly
        }

        It 'Restores ACL after writing' {
            Invoke-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Restore-FileAcl -Times 1 -Exactly
        }

        It 'Restarts TermService after writing' {
            Invoke-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Start-TermService -Times 1 -Exactly
        }

        It 'Creates both pre and post enforcement snapshots' {
            Invoke-Enforcement -Confirm:$false | Out-Null

            Should -Invoke New-StoreSnapshot -Times 2 -Exactly
        }

        It 'Creates an audit record' {
            Invoke-Enforcement -Confirm:$false | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 1 -Exactly
        }
    }

    Context 'Elevation required' {

        BeforeAll {
            Mock Test-IsElevated { $false }
            Mock Test-Path { $true }
        }

        It 'Throws SecurityException when not elevated' {
            { Invoke-Enforcement -Confirm:$false } |
                Should -Throw -ExceptionType ([System.Security.SecurityException])
        }
    }

    Context 'Target binary missing' {

        BeforeAll {
            Mock Test-IsElevated { $true }
            Mock Test-Path { $false }
        }

        It 'Throws FileNotFoundException when the binary does not exist' {
            { Invoke-Enforcement -Confirm:$false } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
        }
    }

    Context 'Snapshot creation failure' {

        BeforeAll {
            Initialize-DefaultEnforcementMock -ServiceRunning

            Mock New-StoreSnapshot { throw 'Database failure' }
        }

        BeforeEach {
            $Script:SignaturePhase = 'Pre'
            $Script:HashSequence   = @($Script:MockPreHash, $Script:MockEnforcedHash)
        }

        It 'Aborts enforcement when snapshot creation fails' {
            { Invoke-Enforcement -Confirm:$false } | Should -Throw
        }

        It 'Does not write bytes when snapshot creation fails' {
            try {
                Invoke-Enforcement -Confirm:$false
            } catch {
                # Suppress the expected exception to allow verification of write count
            }

            Should -Invoke Write-BinaryByte -Times 0
        }
    }

    Context 'Signature not found' {

        BeforeAll {
            Initialize-DefaultEnforcementMock -ServiceRunning

            Mock Find-BinarySignature { $Script:MockSignatureNotFound }
        }

        BeforeEach {
            $Script:HashSequence = @($Script:MockPreHash, $Script:MockEnforcedHash)
        }

        It 'Throws when no compatible signature exists in the binary' {
            { Invoke-Enforcement -Confirm:$false } | Should -Throw
        }

        It 'Does not stop the service when signature discovery fails' {
            try {
                Invoke-Enforcement -Confirm:$false
            } catch {
                # Suppress the expected exception to allow verification of service stop count
            }

            Should -Invoke Stop-TermService -Times 0
        }
    }

    Context 'Service already stopped' {

        BeforeAll {
            Initialize-DefaultEnforcementMock
        }

        BeforeEach {
            $Script:SignaturePhase = 'Pre'
            $Script:HashSequence   = @($Script:MockPreHash, $Script:MockEnforcedHash)
        }

        It 'Does not stop TermService when already stopped' {
            Invoke-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Stop-TermService -Times 0
        }

        It 'Does not restart TermService when it was not running' {
            Invoke-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Start-TermService -Times 0
        }
    }

    Context 'Post-enforcement validation failure' {

        BeforeAll {
            Initialize-DefaultEnforcementMock -ServiceRunning -PostValidationFails
        }

        BeforeEach {
            $Script:SignaturePhase = 'Pre'
            $Script:HashSequence   = @($Script:MockPreHash, $Script:MockEnforcedHash)
        }

        It 'Throws when the original signature still exists after writing' {
            { Invoke-Enforcement -Confirm:$false } | Should -Throw
        }
    }

    Context 'Write failure cleanup' {

        BeforeAll {
            Initialize-DefaultEnforcementMock -ServiceRunning

            Mock Write-BinaryByte { throw 'Write failure' }
        }

        BeforeEach {
            $Script:SignaturePhase = 'Pre'
            $Script:HashSequence   = @($Script:MockPreHash, $Script:MockEnforcedHash)
        }

        It 'Restores ACL even when writing fails' {
            try {
                Invoke-Enforcement -Confirm:$false
            } catch {
                # Suppress the expected exception to allow verification of ACL restore
            }

            Should -Invoke Restore-FileAcl -Times 1
        }

        It 'Restarts TermService even when writing fails' {
            try {
                Invoke-Enforcement -Confirm:$false
            } catch {
                # Suppress the expected exception to allow verification of service restart
            }

            Should -Invoke Start-TermService -Times 1
        }

        It 'Propagates the write failure exception' {
            { Invoke-Enforcement -Confirm:$false } | Should -Throw
        }
    }

    Context 'WhatIf support' {

        BeforeAll {
            Mock Test-IsElevated { $true }
            Mock Test-Path { $true }
            Mock Read-PEFile { }
            Mock Write-BinaryByte { }
        }

        It 'Does not perform enforcement operations when -WhatIf is specified' {
            Invoke-Enforcement -WhatIf

            Should -Invoke Read-PEFile -Times 0
            Should -Invoke Write-BinaryByte -Times 0
        }
    }
}
