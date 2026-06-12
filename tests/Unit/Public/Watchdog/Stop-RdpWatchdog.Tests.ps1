#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Store/Core/Assert-RdpEnvironment.ps1"
    . "$PSScriptRoot/../../../../src/Private/Store/Core/New-StoreAuditRecord.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Test-IsElevated.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-WatchdogTask.ps1"
    . "$PSScriptRoot/../../../../src/Public/Watchdog/Stop-RdpWatchdog.ps1"
}

Describe 'Stop-RdpWatchdog' {

    BeforeEach {
        Mock Assert-RdpEnvironment {}
        Mock Test-IsElevated { $true }
        Mock Get-WatchdogTask { }
        Mock Unregister-ScheduledTask { }
        Mock New-StoreAuditRecord { }
    }

    Context 'Elevation requirement' {

        It 'Throws when not elevated' {
            Mock Test-IsElevated { $false }

            { Stop-RdpWatchdog -Force } | Should -Throw -ErrorId 'ElevationRequired,*'
        }

        It 'Does not check the task when not elevated' {
            Mock Test-IsElevated { $false }

            { Stop-RdpWatchdog -Force } | Should -Throw

            Should -Invoke Get-WatchdogTask -Times 0
        }
    }

    Context 'Task not registered' {

        It 'Returns NotRegistered status' {
            Mock Get-WatchdogTask { $null }

            $result = Stop-RdpWatchdog -Force 3>$null

            $result.Status | Should -Be 'NotRegistered'
            $result.StoppedAt | Should -BeNullOrEmpty
        }

        It 'Warns when task does not exist' {
            Mock Get-WatchdogTask { $null }

            $warnings = Stop-RdpWatchdog -Force 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
                ForEach-Object Message

            ($warnings -join "`n") | Should -Match 'is not registered'
        }

        It 'Does not call Unregister-ScheduledTask when task does not exist' {
            Mock Get-WatchdogTask { $null }

            Stop-RdpWatchdog -Force 3> $null

            Should -Invoke Unregister-ScheduledTask -Times 0
        }
    }

    Context 'Task registered' {

        BeforeEach {
            Mock Get-WatchdogTask {
                [PSCustomObject]@{
                    TaskName = 'RDPControl Watchdog'
                    TaskPath = '\RDPControl\'
                    State    = 'Ready'
                }
            }
        }

        It 'Unregisters the scheduled task' {
            Stop-RdpWatchdog -Force | Out-Null

            Should -Invoke Unregister-ScheduledTask -Times 1
        }

        It 'Writes an audit record' {
            Stop-RdpWatchdog -Force | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 1
        }

        It 'Returns Stopped status with timestamp' {
            $result = Stop-RdpWatchdog -Force

            $result.Status | Should -Be 'Stopped'
            $result.StoppedAt | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        }
    }

    Context 'ShouldProcess support' {

        It 'Does not unregister when -WhatIf is specified' {
            Mock Get-WatchdogTask {
                [PSCustomObject]@{
                    State = 'Ready'
                }
            }

            Stop-RdpWatchdog -WhatIf

            Should -Invoke Unregister-ScheduledTask -Times 0
        }
    }

    Context 'Error handling' {

        It 'Wraps Unregister-ScheduledTask failures' {
            Mock Get-WatchdogTask {
                [PSCustomObject]@{
                    State = 'Ready'
                }
            }

            Mock Unregister-ScheduledTask { throw 'Boom' }

            { Stop-RdpWatchdog -Force } | Should -Throw -ErrorId 'StopWatchdogFailed,*'
        }
    }
}
