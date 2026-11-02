#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Store/Core/Assert-RdpEnvironment.ps1"
    . "$PSScriptRoot/../../../../src/Private/Store/Core/New-StoreAuditRecord.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Test-IsElevated.ps1"
    . "$PSScriptRoot/../../../../src/Private/Enforcement/Test-EnforcementState.ps1"
    . "$PSScriptRoot/../../../../src/Private/Enforcement/Invoke-Enforcement.ps1"
    . "$PSScriptRoot/../../../../src/Public/Watchdog/Invoke-RdpWatchdog.ps1"

    if (-not $env:SystemRoot) {
        $env:SystemRoot = 'C:\Windows'
    }

    # Emits a terminating error with a stable ErrorId, as the private
    # orchestrator does, so ErrorId propagation can be asserted.
    function Invoke-SignatureNotFoundFailure {
        [CmdletBinding()]
        param ()

        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('Target instruction signature was not found.'),
                'SignatureNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                'termsrv.dll'
            )
        )
    }
}

Describe 'Invoke-RdpWatchdog' {

    BeforeEach {
        Mock Assert-RdpEnvironment {}
        Mock Test-IsElevated { $true }
        Mock Test-EnforcementState { $false }
        Mock Invoke-Enforcement {
            [pscustomobject]@{
                Success     = $true
                SnapshotId  = 7
                WriteOffset = '0x0006A5BC'
                Hash        = 'abc123'
                EnforcedAt  = '2026-09-11T14:35:54.0000000Z'
            }
        }
        Mock New-StoreAuditRecord {}
    }

    Context 'Elevation requirement' {

        It 'Throws when not elevated' {
            Mock Test-IsElevated { $false }

            { Invoke-RdpWatchdog -Confirm:$false } | Should -Throw -ErrorId 'ElevationRequired,*'
        }
    }

    Context 'Enforcement state intact' {

        BeforeEach {
            Mock Test-EnforcementState { $true }
        }

        It 'Does nothing and writes no audit record' {
            $result = Invoke-RdpWatchdog -Confirm:$false

            $result.Action   | Should -Be 'None'
            $result.Enforced | Should -BeTrue
            Should -Invoke Invoke-Enforcement -Times 0
            Should -Invoke New-StoreAuditRecord -Times 0
        }
    }

    Context 'Enforcement state drifted' {

        It 'Re-applies enforcement once with the nested prompt suppressed' {
            Invoke-RdpWatchdog -Confirm:$false | Out-Null

            Should -Invoke Invoke-Enforcement -Times 1 -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Confirm') -and -not $PesterBoundParameters['Confirm']
            }
        }

        It 'Writes a Reapplied audit record with the enforced hash' {
            Invoke-RdpWatchdog -Confirm:$false | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 1 -ParameterFilter {
                $Operation -eq 'Invoke-RdpWatchdog' -and $Details -like 'Result=Reapplied;Hash=abc123*'
            }
        }

        It 'Reports Action Reapplied with enforcement details' {
            $result = Invoke-RdpWatchdog -Confirm:$false

            $result.PSObject.TypeNames[0] | Should -Be 'RDPControl.WatchdogRunResult'
            $result.Action      | Should -Be 'Reapplied'
            $result.Enforced    | Should -BeTrue
            $result.Hash        | Should -Be 'abc123'
            $result.SnapshotId  | Should -Be 7
            $result.WriteOffset | Should -Be '0x0006A5BC'
            $result.CheckedAt   | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        }
    }

    Context 'ShouldProcess support' {

        It 'Does not re-apply enforcement when -WhatIf is specified' {
            Invoke-RdpWatchdog -WhatIf

            Should -Invoke Invoke-Enforcement -Times 0
            Should -Invoke New-StoreAuditRecord -Times 0
        }
    }

    Context 'Error handling' {

        It 'Writes a Failed audit record and re-throws' {
            Mock Invoke-Enforcement { throw 'Boom' }

            { Invoke-RdpWatchdog -Confirm:$false } | Should -Throw -ExpectedMessage '*Boom*'

            Should -Invoke New-StoreAuditRecord -Times 1 -ParameterFilter {
                $Operation -eq 'Invoke-RdpWatchdog' -and $Details -like 'Result=Failed;Error=Boom*'
            }
        }

        It 'Preserves the ErrorId of enforcement failures' {
            Mock Invoke-Enforcement { Invoke-SignatureNotFoundFailure }

            { Invoke-RdpWatchdog -Confirm:$false } | Should -Throw -ErrorId 'SignatureNotFound,*'
        }

        It 'Does not mask the enforcement error when the audit write fails' {
            Mock Invoke-Enforcement { throw 'Boom' }
            Mock New-StoreAuditRecord { throw 'Database locked' }

            { Invoke-RdpWatchdog -Confirm:$false -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage '*Boom*'
        }
    }
}
