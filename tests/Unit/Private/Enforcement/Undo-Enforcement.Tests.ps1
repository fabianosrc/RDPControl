Describe 'Undo-Enforcement' {

    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-BinaryHash.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Get-PEArchitecture.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Read-PEFile.ps1"
        . "$PSScriptRoot/../../../../src/Private/Assembly/Write-BinaryContent.ps1"
        . "$PSScriptRoot/../../../../src/Private/Engine/Test-IsElevated.ps1"
        . "$PSScriptRoot/../../../../src/Private/Engine/Stop-TermService.ps1"
        . "$PSScriptRoot/../../../../src/Private/Engine/Start-TermService.ps1"
        . "$PSScriptRoot/../../../../src/Private/Engine/Grant-ProtectedFileAccess.ps1"
        . "$PSScriptRoot/../../../../src/Private/Engine/Restore-FileAcl.ps1"
        . "$PSScriptRoot/../../../../src/Private/Store/Core/Get-StoreSnapshot.ps1"
        . "$PSScriptRoot/../../../../src/Private/Store/Core/New-StoreAuditRecord.ps1"
        . "$PSScriptRoot/../../../../src/Private/Enforcement/Undo-Enforcement.ps1"

        #
        # Shared fixtures
        #

        $Script:MockHash = 'aaa111aaa111aaa111aaa111aaa111aaa111aaa111aaa111aaa111aaa111aaaa'

        $Script:MockBlobBytes = [byte[]](0x4D, 0x5A, 0x90, 0x00)

        $Script:MockAssembly = [PSCustomObject]@{
            PSTypeName   = 'RDPControl.PEFile'
            Bytes        = $Script:MockBlobBytes
            Architecture = 'x64'
            Path         = 'C:\Windows\System32\termsrv.dll'
        }

        $Script:MockSnapshot = [PSCustomObject]@{
            id             = 5
            binary_version = '10.0.19041.1'
            sha256         = $Script:MockHash
            enforced       = $false
            binary_blob    = $Script:MockBlobBytes
        }

        $Script:MockAcl = [System.Security.AccessControl.FileSecurity]::new()

        $Script:RunningService = [PSCustomObject]@{
            Name   = 'TermService'
            Status = 'Running'
        }

        $Script:StoppedService = [PSCustomObject]@{
            Name   = 'TermService'
            Status = 'Stopped'
        }

        function Initialize-UndoMock {
            param (
                [switch]$ServiceRunning,
                [string]$CurrentHash = $Script:MockHash,
                [object]$Snapshot = $Script:MockSnapshot
            )

            $Script:ActiveSnapshot = $Snapshot
            $Script:ActiveHash     = $CurrentHash

            Mock Test-IsElevated { $true }

            Mock Test-Path { $true }

            Mock Get-StoreSnapshot { $Script:ActiveSnapshot }

            Mock Read-PEFile { $Script:MockAssembly }

            Mock Get-BinaryHash { $Script:ActiveHash }

            Mock Get-Acl { $Script:MockAcl }

            Mock Grant-ProtectedFileAccess { }

            Mock Restore-FileAcl { }

            Mock Stop-TermService { }

            Mock Start-TermService { }

            Mock New-StoreAuditRecord { 1 }

            Mock Write-BinaryContent { }
            if ($ServiceRunning) {
                Mock Get-Service { $Script:RunningService }
            } else {
                Mock Get-Service { $Script:StoppedService }
            }
        }
    }

    Context 'Successful restore' {

        BeforeEach {
            Initialize-UndoMock -ServiceRunning
        }

        It 'Returns a successful orchestration result' {
            $result = Undo-Enforcement -Confirm:$false

            $result.Success | Should -BeTrue

            $result.SnapshotId | Should -BeExactly 5

            $result.Hash | Should -BeExactly $Script:MockHash

            $result.RestoredAt | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }

        It 'Returns a typed result object' {
            $result = Undo-Enforcement -Confirm:$false

            $result.PSObject.TypeNames | Should -Contain 'RDPControl.EnforcementUndoResult'
        }

        It 'Stops TermService before restore operations' {
            Undo-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Stop-TermService -Times 1 -Exactly
        }

        It 'Restarts TermService after restore operations' {
            Undo-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Start-TermService -Times 1 -Exactly
        }

        It 'Restores the original ACL after restore operations' {
            Undo-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Restore-FileAcl -Times 1 -Exactly
        }

        It 'Validates the restored binary hash' {
            Undo-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Read-PEFile -Times 1 -Exactly

            Should -Invoke Get-BinaryHash -Times 1 -Exactly
        }

        It 'Writes an audit record' {
            Undo-Enforcement -Confirm:$false | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 1 -Exactly
        }
    }

    Context 'Explicit snapshot selection' {

        BeforeEach {
            Initialize-UndoMock -ServiceRunning
        }

        It 'Queries the requested snapshot id' {
            Undo-Enforcement -SnapshotId 3 -Confirm:$false | Out-Null

            Should -Invoke Get-StoreSnapshot -Times 1 -Exactly -ParameterFilter { $Id -eq 3 }
        }
    }

    Context 'Elevation requirements' {

        BeforeEach {
            Mock Test-IsElevated { $false }

            Mock Test-Path { $true }
        }

        It 'Throws SecurityException when not elevated' {
            { Undo-Enforcement -Confirm:$false } |
                Should -Throw -ExceptionType ([System.Security.SecurityException])
        }
    }

    Context 'Target binary validation' {

        BeforeEach {
            Mock Test-IsElevated { $true }

            Mock Test-Path { $false }
        }

        It 'Throws FileNotFoundException when the binary does not exist' {
            { Undo-Enforcement -Confirm:$false } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
        }
    }

    Context 'Snapshot retrieval failures' {

        BeforeEach {
            Initialize-UndoMock -ServiceRunning -Snapshot $null
        }

        It 'Throws when no snapshot is available' {
            { Undo-Enforcement -Confirm:$false } | Should -Throw
        }

        It 'Does not attempt service orchestration when snapshot retrieval fails' {

            try {
                Undo-Enforcement -Confirm:$false
            } catch {

            }

            Should -Invoke Stop-TermService -Times 0

            Should -Invoke Start-TermService -Times 0
        }
    }

    Context 'Snapshot integrity validation' {

        BeforeEach {

            Initialize-UndoMock -ServiceRunning

            Mock Get-StoreSnapshot {
                [PSCustomObject]@{
                    id             = 5
                    binary_version = '10.0.19041.1'
                    sha256         = $Script:MockHash
                    enforced       = $false
                    binary_blob    = $null
                }
            }
        }

        It 'Throws when snapshot binary data is missing' {
            { Undo-Enforcement -Confirm:$false } | Should -Throw
        }
    }

    Context 'Post-restore validation failure' {

        BeforeEach {

            Initialize-UndoMock `
                -ServiceRunning `
                -CurrentHash 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
        }

        It 'Throws when restored hash does not match snapshot hash' {
            { Undo-Enforcement -Confirm:$false } | Should -Throw
        }
    }

    Context 'Service state orchestration' {

        BeforeEach {
            Initialize-UndoMock
        }

        It 'Does not stop TermService when already stopped' {
            Undo-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Stop-TermService -Times 0
        }

        It 'Does not restart TermService when it was not running' {
            Undo-Enforcement -Confirm:$false | Out-Null

            Should -Invoke Start-TermService -Times 0
        }
    }

    Context 'Failure cleanup guarantees' {

        BeforeEach {

            Initialize-UndoMock -ServiceRunning

            Mock Grant-ProtectedFileAccess { throw 'Access denied' }
        }

        It 'Always restores ACL during rollback cleanup' {

            try {
                Undo-Enforcement -Confirm:$false
            } catch {

            }

            Should -Invoke Restore-FileAcl -Times 1 -Exactly
        }

        It 'Always restarts TermService during rollback cleanup' {
            try {
                Undo-Enforcement -Confirm:$false
            } catch {

            }

            Should -Invoke Start-TermService -Times 1 -Exactly
        }

        It 'Propagates the original failure' {
            { Undo-Enforcement -Confirm:$false } | Should -Throw
        }
    }

    Context 'WhatIf support' {

        BeforeEach {
            Mock Test-IsElevated { $true }

            Mock Test-Path { $true }

            Mock Get-StoreSnapshot { }
        }

        It 'Does not execute restore operations when -WhatIf is specified' {
            Undo-Enforcement -WhatIf

            Should -Invoke Get-StoreSnapshot -Times 0
        }
    }
}
