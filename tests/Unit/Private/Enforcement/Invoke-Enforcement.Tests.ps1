Describe 'Test-EnforcementState' {

    BeforeAll {

        . "$PSScriptRoot/../../../../src/Private/Assembly/Read-PEFile.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BinaryHash.ps1"
        . "$PSScriptRoot/../../../../src/Private/Store/Core/Get-StoreSnapshot.ps1"
        . "$PSScriptRoot/../../../../src/Private/Enforcement/Test-EnforcementState.ps1"

        #
        # Stable mock data
        #

        $Script:MockHash = (
            'abc123def456abc123def456abc123def456abc123def456abc123def456abcd'
        )

        $Script:MockAssembly = [pscustomobject]@{
            PSTypeName   = 'RDPControl.PEFile'
            Bytes        = [byte[]](0x4D, 0x5A, 0x00, 0x00)
            Architecture = 'x64'
            Path         = 'C:\Windows\System32\termsrv.dll'
        }
    }

    Context 'Enforcement is active' {

        BeforeAll {
            Mock Test-Path { $true }

            Mock Get-StoreSnapshot {
                [PSCustomObject]@{
                    id       = 1
                    sha256   = $Script:MockHash
                    enforced = $true
                }
            }

            Mock Read-PEFile { $Script:MockAssembly }

            Mock Get-BinaryHash { $Script:MockHash }
        }

        It 'Returns $true when current hash matches enforced snapshot' {
            $result = Test-EnforcementState

            $result | Should -BeTrue
        }

        It 'Reads the target PE image' {
            Test-EnforcementState | Out-Null

            Should -Invoke Read-PEFile -Times 1 -Exactly
        }

        It 'Computes the SHA256 hash from the PE bytes' {
            Test-EnforcementState | Out-Null

            Should -Invoke Get-BinaryHash -Times 1 -Exactly
        }

        It 'Queries the enforced snapshot from the store' {
            Test-EnforcementState | Out-Null

            Should -Invoke Get-StoreSnapshot -Times 1 -Exactly
        }

        It 'Checks whether the target binary exists' {
            Test-EnforcementState | Out-Null

            Should -Invoke Test-Path -Times 1 -Exactly
        }
    }

    Context 'Enforcement is not active (hash mismatch)' {

        BeforeAll {
            Mock Test-Path { $true }

            Mock Get-StoreSnapshot {
                [PSCustomObject]@{
                    id       = 1
                    sha256   = ('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
                    enforced = $true
                }
            }

            Mock Read-PEFile { $Script:MockAssembly }

            Mock Get-BinaryHash { $Script:MockHash }
        }

        It 'Returns $false when the current hash differs from the enforced snapshot' {
            $result = Test-EnforcementState

            $result |  Should -BeFalse
        }
    }

    Context 'No enforced snapshot exists' {

        BeforeAll {
            Mock Test-Path { $true }

            Mock Get-StoreSnapshot { $null }

            Mock Read-PEFile { $Script:MockAssembly }

            Mock Get-BinaryHash { $Script:MockHash }
        }

        It 'Returns $false when no enforced snapshot is available' {
            $result = Test-EnforcementState

            $result | Should -BeFalse
        }

        It 'Does not read the PE image when no snapshot exists' {
            Test-EnforcementState | Out-Null

            Should -Invoke Read-PEFile -Times 0
        }

        It 'Does not compute the binary hash when no snapshot exists' {
            Test-EnforcementState | Out-Null

            Should -Invoke Get-BinaryHash -Times 0
        }
    }

    Context 'Target binary not found' {

        BeforeAll {
            Mock Test-Path { $false }
        }

        It 'Throws FileNotFoundException when the target binary does not exist' {
            { Test-EnforcementState } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
        }

        It 'Does not query the store when the binary is missing' {
            Mock Get-StoreSnapshot { }

            { Test-EnforcementState | Out-Null } | Should -Throw

            Should -Invoke Get-StoreSnapshot -Times 0
        }
    }

    Context 'Output type' {

        BeforeAll {
            Mock Test-Path { $true }

            Mock Get-StoreSnapshot {
                [PSCustomObject]@{
                    id       = 1
                    sha256   = $Script:MockHash
                    enforced = $true
                }
            }

            Mock Read-PEFile { $Script:MockAssembly }

            Mock Get-BinaryHash { $Script:MockHash }
        }

        It 'Returns a System.Boolean' {
            $result = Test-EnforcementState

            $result | Should -BeOfType ([bool])
        }
    }

    Context 'Case-insensitive hash comparison' {

        BeforeAll {
            Mock Test-Path { $true }

            Mock Get-StoreSnapshot {
                [PSCustomObject]@{
                    id       = 1
                    sha256   = ('abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890')
                    enforced = $true
                }
            }

            Mock Read-PEFile { $Script:MockAssembly }

            Mock Get-BinaryHash { 'ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890' }
        }

        It 'Returns $true regardless of hash casing' {
            $result = Test-EnforcementState

            $result | Should -BeTrue
        }
    }

    Context 'Snapshot integrity' {

        BeforeAll {
            Mock Test-Path { $true }

            Mock Read-PEFile { $Script:MockAssembly }

            Mock Get-BinaryHash { $Script:MockHash }
        }

        It 'Returns $false when snapshot SHA256 is null' {
            Mock Get-StoreSnapshot {
                [PSCustomObject]@{
                    id       = 1
                    sha256   = $null
                    enforced = $true
                }
            }

            $result = Test-EnforcementState

            $result | Should -BeFalse
        }

        It 'Returns $false when snapshot SHA256 is empty' {
            Mock Get-StoreSnapshot {
                [PSCustomObject]@{
                    id       = 1
                    sha256   = ''
                    enforced = $true
                }
            }

            $result = Test-EnforcementState

            $result | Should -BeFalse
        }
    }
}
