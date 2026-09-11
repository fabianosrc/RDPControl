#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Store/Core/Assert-RdpEnvironment.ps1"
    . "$PSScriptRoot/../../../../src/Private/Store/Core/New-StoreAuditRecord.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Test-IsElevated.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-WatchdogTask.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/New-WatchdogTaskTrigger.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/New-WatchdogTaskAction.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Register-WatchdogTask.ps1"
    . "$PSScriptRoot/../../../../src/Private/Enforcement/Test-EnforcementState.ps1"
    . "$PSScriptRoot/../../../../src/Public/Watchdog/Start-RdpWatchdog.ps1"
}

Describe 'Start-RdpWatchdog' {

    BeforeEach {
        Mock Assert-RdpEnvironment {}
        Mock Test-IsElevated { $true }
        Mock Test-EnforcementState { $true }
        Mock Get-WatchdogTask { $null }
        Mock Get-Module { [pscustomobject]@{ ModuleBase = 'C:\Modules\RDPControl' } }
        Mock New-WatchdogTaskAction { [pscustomobject]@{ Execute = 'powershell.exe' } }
        Mock New-WatchdogTaskTrigger { [pscustomobject]@{ Enabled = $true } }
        Mock New-ScheduledTaskSettingsSet { [pscustomobject]@{} }
        Mock New-ScheduledTaskPrincipal { [pscustomobject]@{ UserId = 'SYSTEM' } }
        Mock Register-WatchdogTask {}
        Mock Unregister-ScheduledTask {}
        Mock New-StoreAuditRecord {}
    }

    Context 'Elevation requirement' {

        It 'Throws when not elevated' {
            Mock Test-IsElevated { $false }

            { Start-RdpWatchdog -Force } | Should -Throw -ErrorId 'ElevationRequired,*'
        }

        It 'Does not register a task when not elevated' {
            Mock Test-IsElevated { $false }

            { Start-RdpWatchdog -Force } | Should -Throw

            Should -Invoke Register-WatchdogTask -Times 0
        }
    }

    Context 'Enforcement requirement' {

        It 'Throws when enforcement is not active' {
            Mock Test-EnforcementState { $false }

            { Start-RdpWatchdog -Force } | Should -Throw -ErrorId 'EnforcementNotActive,*'
        }

        It 'Does not register a task when enforcement is not active' {
            Mock Test-EnforcementState { $false }

            { Start-RdpWatchdog -Force } | Should -Throw

            Should -Invoke Register-WatchdogTask -Times 0
        }

        It 'Enforcement check is not bypassed by -Force' {
            Mock Test-EnforcementState { $false }

            { Start-RdpWatchdog -Force } | Should -Throw -ErrorId 'EnforcementNotActive,*'
        }
    }

    Context 'Module availability' {

        It 'Throws when RDPControl module is not loaded' {
            Mock Get-Module { $null }

            { Start-RdpWatchdog -Force } | Should -Throw -ErrorId 'ModuleNotLoaded,*'
        }

        It 'Does not register a task when module is not loaded' {
            Mock Get-Module { $null }

            { Start-RdpWatchdog -Force } | Should -Throw

            Should -Invoke Register-WatchdogTask -Times 0
        }
    }

    Context 'ShouldProcess support' {

        It 'Does not register a task when -WhatIf is specified' {
            Start-RdpWatchdog -WhatIf

            Should -Invoke Register-WatchdogTask -Times 0
        }

        It 'Does not throw module/enforcement errors before ShouldProcess when -WhatIf is specified' {
            { Start-RdpWatchdog -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Task registration' {

        It 'Registers a new task when none exists' {
            Mock Get-WatchdogTask { $null }

            Start-RdpWatchdog -Force | Out-Null

            Should -Invoke Register-WatchdogTask -Times 1
            Should -Invoke Unregister-ScheduledTask -Times 0
        }

        It 'Unregisters an existing task before registering a new one' {
            Mock Get-WatchdogTask {
                [pscustomobject]@{ State = 'Ready' }
            }

            Start-RdpWatchdog -Force | Out-Null

            Should -Invoke Unregister-ScheduledTask -Times 1 -ParameterFilter {
                $TaskName -eq 'RDPControl Watchdog' -and $TaskPath -eq '\RDPControl\'
            }
            Should -Invoke Register-WatchdogTask -Times 1
        }

        It 'Creates a single boot trigger' {
            Start-RdpWatchdog -Force | Out-Null

            Should -Invoke New-WatchdogTaskTrigger -Times 1
        }

        It 'Registers the task with the boot trigger' {
            Start-RdpWatchdog -Force | Out-Null

            Should -Invoke Register-WatchdogTask -Times 1 -ParameterFilter {
                $Trigger.Count -eq 1
            }
        }

        It 'Builds the task action for the loaded module path' {
            Start-RdpWatchdog -Force | Out-Null

            Should -Invoke New-WatchdogTaskAction -Times 1 -ParameterFilter {
                $ModulePath -eq 'C:\Modules\RDPControl'
            }
        }

        It 'Runs the task as the SYSTEM service account with highest privileges' {
            Start-RdpWatchdog -Force | Out-Null

            Should -Invoke New-ScheduledTaskPrincipal -Times 1 -ParameterFilter {
                $UserId -eq 'SYSTEM' -and
                "$LogonType" -eq 'ServiceAccount' -and
                "$RunLevel" -eq 'Highest'
            }
        }

        It 'Writes an audit record' {
            Start-RdpWatchdog -Force | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 1
        }
    }

    Context 'Module location' {

        It 'Warns when the module is loaded from a network path' {
            Mock Get-Module { [pscustomobject]@{ ModuleBase = '\\wsl.localhost\Debian\home\user\RDPControl' } }

            Start-RdpWatchdog -Force -WarningAction SilentlyContinue -WarningVariable warnings | Out-Null

            $warnings | Should -Not -BeNullOrEmpty
            $warnings[0].Message | Should -Match 'SYSTEM'
        }

        It 'Does not warn for a local module path' {
            Start-RdpWatchdog -Force -WarningAction SilentlyContinue -WarningVariable warnings | Out-Null

            $warnings | Should -BeNullOrEmpty
        }
    }

    Context 'Return contract' {

        It 'Returns Running status with task metadata' {
            $result = Start-RdpWatchdog -Force

            $result.Status    | Should -Be 'Running'
            $result.TaskName  | Should -Be 'RDPControl Watchdog'
            $result.TaskPath  | Should -Be '\RDPControl\'
            $result.StartedAt | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        }
    }

    Context 'Error handling' {

        It 'Wraps Register-WatchdogTask failures' {
            Mock Register-WatchdogTask { throw 'Boom' }

            { Start-RdpWatchdog -Force } | Should -Throw -ErrorId 'StartWatchdogFailed,*'
        }

        It 'Wraps New-WatchdogTaskTrigger failures' {
            Mock New-WatchdogTaskTrigger { throw 'Trigger failure' }

            { Start-RdpWatchdog -Force } | Should -Throw -ErrorId 'StartWatchdogFailed,*'
        }

        It 'Wraps New-WatchdogTaskAction failures' {
            Mock New-WatchdogTaskAction { throw 'Action failure' }

            { Start-RdpWatchdog -Force } | Should -Throw -ErrorId 'StartWatchdogFailed,*'
        }
    }
}
