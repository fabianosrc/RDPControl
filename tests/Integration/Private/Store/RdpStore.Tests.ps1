#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Integration tests for the RDPControl Store layer.

.DESCRIPTION
Verifies Initialize-RdpStore, New-StoreSnapshot, Get-StoreSnapshot,
Remove-StoreSnapshot, New-StoreAuditRecord and Get-StoreAuditRecord
against a real SQLite database.

These tests require Windows and an elevated PowerShell session.
Initialize-RdpEnvironment always writes to $env:ProgramData\RDPControl
and requires elevation. When the required environment is unavailable,
the suite is skipped.

Coverage includes:
  - Initialize-RdpStore creates the database.
  - New-StoreSnapshot returns the new snapshot ID.
  - New-StoreSnapshot is idempotent for the same SHA256.
  - Get-StoreSnapshot returns the stored snapshot.
  - Get-StoreSnapshot filters by Sha256.
  - Get-StoreSnapshot returns the latest snapshot.
  - Get-StoreSnapshot includes the blob when requested.
  - Get-StoreSnapshot does not include the blob by default.
  - Remove-StoreSnapshot removes the snapshot.
  - Remove-StoreSnapshot protects the last snapshot when enforced.
  - New-StoreAuditRecord returns the new audit record ID.
  - Get-StoreAuditRecord returns stored records.
  - Get-StoreAuditRecord filters by operation.
  - Get-StoreAuditRecord returns the latest record.
#>

# InModuleScope needs to resolve the PipeDFe module during the Discovery phase,
# because that's when Context/It are executed to register the test tree. If the
# module isn't loaded at that point, InModuleScope fails before any BeforeAll or
# BeforeEach ever runs.
BeforeDiscovery {
    $moduleRoot = (Get-Item -LiteralPath $PSScriptRoot).Parent.Parent.Parent.Parent.FullName

    $moduleManifest = Join-Path -Path $moduleRoot -ChildPath 'RDPControl.psd1'

    Import-Module -Name $moduleManifest -Force -Global -ErrorAction Stop

    $isWindowsPlatform = (
        [System.Environment]::OSVersion.Platform -eq
        [System.PlatformID]::Win32NT
    )

    $isElevated = $false

    if ($isWindowsPlatform) {
        $identity   = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal  = [System.Security.Principal.WindowsPrincipal]::new($identity)
        $isElevated = $principal.IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }

    $Script:SkipIntegration = -not ($isWindowsPlatform -and $isElevated)
}

Describe 'RDPControl Store' -Tag 'Integration' -Skip:$Script:SkipIntegration {

    InModuleScope -ModuleName RDPControl {

        BeforeAll {

            $envParams = @{
                Force   = $true
                Confirm = $false
            }

            Initialize-RdpEnvironment @envParams | Out-Null

            $Script:SampleBlob    = [byte[]](1, 2, 3, 4, 5)
            $Script:SamplePath    = 'C:\Windows\System32\termsrv.dll'
            $Script:SampleVersion = '10.0.19041.1'
            $Script:SampleBuild   = '19041'
        }

        #region Initialize-RdpStore
        Context 'Initialize-RdpStore' {

            It 'Creates the database file' {
                $basePath = Join-Path -Path $env:ProgramData -ChildPath 'RDPControl\database'

                $dbFiles = @(
                    Get-ChildItem -Path $basePath -Filter '*.db' -ErrorAction SilentlyContinue
                )

                $dbFiles.Count | Should -BeGreaterThan 0
            }
        }
        #endregion

        #region New-StoreSnapshot
        Context 'New-StoreSnapshot' {

            It 'Returns the new snapshot ID' {
                $snapshotParams = @{
                    BinaryPath    = $Script:SamplePath
                    BinaryVersion = $Script:SampleVersion
                    OsBuild       = $Script:SampleBuild
                    Sha256        = [System.Guid]::NewGuid().ToString('N')
                    BinaryBlob    = $Script:SampleBlob
                    Enforced      = $false
                    Confirm       = $false
                }

                $id = New-StoreSnapshot @snapshotParams

                $id | Should -BeGreaterThan 0
            }

            It 'Is idempotent for the same SHA256' {
                $uniqueHash = [System.Guid]::NewGuid().ToString('N')

                $snapshotParams = @{
                    BinaryPath    = $Script:SamplePath
                    BinaryVersion = $Script:SampleVersion
                    OsBuild       = $Script:SampleBuild
                    Sha256        = $uniqueHash
                    BinaryBlob    = $Script:SampleBlob
                    Enforced      = $false
                    Confirm       = $false
                }

                $id1 = New-StoreSnapshot @snapshotParams
                $id2 = New-StoreSnapshot @snapshotParams

                $id1 | Should -Be $id2
            }
        }
        #endregion

        #region Get-StoreSnapshot
        Context 'Get-StoreSnapshot' {

            BeforeEach {

                $Script:SnapshotHash = [System.Guid]::NewGuid().ToString('N')

                $snapshotParams = @{
                    BinaryPath    = $Script:SamplePath
                    BinaryVersion = $Script:SampleVersion
                    OsBuild       = $Script:SampleBuild
                    Sha256        = $Script:SnapshotHash
                    BinaryBlob    = $Script:SampleBlob
                    Enforced      = $false
                    Confirm       = $false
                }

                $Script:SnapshotId = New-StoreSnapshot @snapshotParams
            }

            It 'Returns the stored snapshot by ID' {
                $result = Get-StoreSnapshot -Id $Script:SnapshotId

                $result            | Should -Not -BeNullOrEmpty
                $result.id         | Should -Be $Script:SnapshotId
            }

            It 'Filters by Sha256' {
                $result = Get-StoreSnapshot -Sha256 $Script:SnapshotHash

                $result        | Should -Not -BeNullOrEmpty
                $result.sha256 | Should -Be $Script:SnapshotHash
            }

            It 'Returns the latest snapshot' {
                $latest = Get-StoreSnapshot -Latest

                $latest    | Should -Not -BeNullOrEmpty
                $latest.id | Should -Be $Script:SnapshotId
            }

            It 'Includes the blob when IncludeBlob is specified' {
                $result = Get-StoreSnapshot -Id $Script:SnapshotId -IncludeBlob

                $result.binary_blob       | Should -Not -BeNullOrEmpty
                $result.binary_blob.Count | Should -Be $Script:SampleBlob.Count
            }

            It 'Does not include the blob by default' {
                $result = Get-StoreSnapshot -Id $Script:SnapshotId

                $hasBlobProperty = $result.PSObject.Properties.Name -contains 'binary_blob'

                $hasBlobProperty | Should -BeFalse
            }
        }
        #endregion

        #region Remove-StoreSnapshot
        Context 'Remove-StoreSnapshot' {

            It 'Removes the snapshot' {
                $uniqueHash = [System.Guid]::NewGuid().ToString('N')

                $snapshotParams = @{
                    BinaryPath    = $Script:SamplePath
                    BinaryVersion = $Script:SampleVersion
                    OsBuild       = $Script:SampleBuild
                    Sha256        = $uniqueHash
                    BinaryBlob    = $Script:SampleBlob
                    Enforced      = $false
                    Confirm       = $false
                }

                $id = New-StoreSnapshot @snapshotParams

                Remove-StoreSnapshot -Id $id -Force

                $result = Get-StoreSnapshot -Id $id

                $result | Should -BeNullOrEmpty
            }

            It 'Protects the last snapshot when enforcement is active' {
                $uniqueHash = [System.Guid]::NewGuid().ToString('N')

                $snapshotParams = @{
                    BinaryPath    = $Script:SamplePath
                    BinaryVersion = $Script:SampleVersion
                    OsBuild       = $Script:SampleBuild
                    Sha256        = $uniqueHash
                    BinaryBlob    = $Script:SampleBlob
                    Enforced      = $true
                    Confirm       = $false
                }

                $id = New-StoreSnapshot @snapshotParams

                $allSnapshots = @(Get-StoreSnapshot)

                if ($allSnapshots.Count -eq 1) {
                    { Remove-StoreSnapshot -Id $id -Force } |
                        Should -Throw -ErrorId 'LastSnapshotProtected,*'
                } else {
                    Set-ItResult -Skipped -Because 'Multiple snapshots exist; protection rule does not apply in this environment.'
                }
            }
        }
        #endregion

        #region New-StoreAuditRecord
        Context 'New-StoreAuditRecord' {

            It 'Returns the new audit record ID' {
                $auditParams = @{
                    Operation = 'Integration-Test'
                    Details   = 'Created by integration test'
                    Confirm   = $false
                }

                $id = New-StoreAuditRecord @auditParams

                $id | Should -BeGreaterThan 0
            }
        }
        #endregion

        #region Get-StoreAuditRecord
        Context 'Get-StoreAuditRecord' {

            BeforeEach {

                $Script:AuditOperation = (
                    'Test-{0}' -f [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
                )

                $auditParams = @{
                    Operation = $Script:AuditOperation
                    Details   = 'Integration test record'
                    Confirm   = $false
                }

                $Script:AuditId = New-StoreAuditRecord @auditParams
            }

            It 'Returns stored records by ID' {
                $result = Get-StoreAuditRecord -Id $Script:AuditId

                $result    | Should -Not -BeNullOrEmpty
                $result.id | Should -Be $Script:AuditId
            }

            It 'Filters by operation' {
                $result = Get-StoreAuditRecord -Operation $Script:AuditOperation

                $result           | Should -Not -BeNullOrEmpty
                $result.operation | Should -Be $Script:AuditOperation
            }

            It 'Returns the latest audit record' {
                $latest = Get-StoreAuditRecord -Latest

                $latest    | Should -Not -BeNullOrEmpty
                $latest.id | Should -Be $Script:AuditId
            }
        }
        #endregion
    }
}
