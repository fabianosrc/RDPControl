#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Store/Core/Assert-RdpEnvironment.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Test-IsElevated.ps1"
    . "$PSScriptRoot/../../../../src/Private/Enforcement/Test-EnforcementState.ps1"
    . "$PSScriptRoot/../../../../src/Private/Enforcement/Invoke-Enforcement.ps1"
    . "$PSScriptRoot/../../../../src/Private/Enforcement/Undo-Enforcement.ps1"
    . "$PSScriptRoot/../../../../src/Public/Policy/Set-RdpSessionMode.ps1"

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

Describe 'Set-RdpSessionMode' {

    BeforeEach {
        Mock Assert-RdpEnvironment {}
        Mock Test-IsElevated { $true }
        Mock Test-EnforcementState { $false }
        Mock Invoke-Enforcement {
            [pscustomobject]@{ SnapshotId = 7; WriteOffset = '0x0006A5BC'; Hash = 'abc123'; EnforcedAt = '2026-09-11T14:35:54.0000000Z' }
        }
        Mock Undo-Enforcement {
            [pscustomobject]@{ SnapshotId = 7; Hash = 'def456'; RestoredAt = '2026-09-11T14:40:00.0000000Z' }
        }
    }

    Context 'Enable' {

        It 'Applies enforcement once with the nested prompt suppressed' {
            Set-RdpSessionMode -Enabled -Force | Out-Null

            Should -Invoke Invoke-Enforcement -Times 1 -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Confirm') -and -not $PesterBoundParameters['Confirm']
            }
        }

        It 'Warns and does nothing when already enabled' {
            Mock Test-EnforcementState { $true }

            Set-RdpSessionMode -Enabled -WarningAction SilentlyContinue -WarningVariable warnings | Out-Null

            $warnings | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-Enforcement -Times 0
        }

        It 'Does not apply enforcement when -WhatIf is specified' {
            Set-RdpSessionMode -Enabled -WhatIf

            Should -Invoke Invoke-Enforcement -Times 0
        }

        It 'Preserves the ErrorId of enforcement failures' {
            Mock Invoke-Enforcement { Invoke-SignatureNotFoundFailure }

            { Set-RdpSessionMode -Enabled -Force } | Should -Throw -ErrorId 'SignatureNotFound,*'
        }
    }

    Context 'Disable' {

        BeforeEach {
            Mock Test-EnforcementState { $true }
        }

        It 'Restores the original binary once with the nested prompt suppressed' {
            Set-RdpSessionMode -Disabled -Force | Out-Null

            Should -Invoke Undo-Enforcement -Times 1 -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Confirm') -and -not $PesterBoundParameters['Confirm']
            }
        }

        It 'Warns and does nothing when not enabled' {
            Mock Test-EnforcementState { $false }

            Set-RdpSessionMode -Disabled -WarningAction SilentlyContinue -WarningVariable warnings | Out-Null

            $warnings | Should -Not -BeNullOrEmpty
            Should -Invoke Undo-Enforcement -Times 0
        }

        It 'Does not restore when -WhatIf is specified' {
            Set-RdpSessionMode -Disabled -WhatIf

            Should -Invoke Undo-Enforcement -Times 0
        }
    }
}
