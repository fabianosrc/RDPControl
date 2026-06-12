#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Store/Core/Assert-RdpEnvironment.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-WatchdogTask.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-WatchdogTaskInfo.ps1"
    . "$PSScriptRoot/../../../../src/Public/Watchdog/Get-RdpWatchdogStatus.ps1"
}

Describe 'Get-RdpWatchdogStatus' {

    BeforeEach {
        Mock Assert-RdpEnvironment { }
        Mock Get-WatchdogTask { }
        Mock Get-WatchdogTaskInfo { }
    }

    Context 'Environment validation' {

        It 'Calls Assert-RdpEnvironment exactly once' {
            Mock Get-WatchdogTask { $null }

            Get-RdpWatchdogStatus | Out-Null

            Should -Invoke Assert-RdpEnvironment -Exactly -Times 1
        }
    }

    Context 'Not registered' {

        It 'Returns NotRegistered when task does not exist' {
            Mock Get-WatchdogTask { $null }

            $result = Get-RdpWatchdogStatus

            $result.Status | Should -Be 'NotRegistered'
            $result.LastRun | Should -BeNullOrEmpty
            $result.NextRun | Should -BeNullOrEmpty
        }

        It 'Does not call Get-WatchdogTaskInfo' {
            Mock Get-WatchdogTask { $null }

            Get-RdpWatchdogStatus | Out-Null

            Should -Invoke Get-WatchdogTaskInfo -Times 0
        }
    }

    Context 'Running states' {

        BeforeEach {
            Mock Get-WatchdogTask {
                [PSCustomObject]@{
                    TaskName = 'RDPControl Watchdog'
                    TaskPath = '\RDPControl\'
                    State    = 'Ready'
                }
            }

            Mock Get-WatchdogTaskInfo {
                [PSCustomObject]@{
                    LastRunTime = [datetime]'2026-01-01T10:00:00Z'
                    NextRunTime = [datetime]'2026-01-02T10:00:00Z'
                }
            }
        }

        It 'Maps Ready to Running' {
            (Get-RdpWatchdogStatus).Status | Should -Be 'Running'
        }

        It 'Returns formatted timestamps' {
            $result = Get-RdpWatchdogStatus

            $result.LastRun |
                Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'

            $result.NextRun |
                Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        }
    }

    Context 'Task state mapping' {

        It 'Maps Running to Running' {
            Mock Get-WatchdogTask {
                [PSCustomObject]@{
                    State = 'Running'
                }
            }

            Mock Get-WatchdogTaskInfo {
                [PSCustomObject]@{}
            }

            (Get-RdpWatchdogStatus).Status | Should -Be 'Running'
        }

        It 'Maps Disabled to Stopped' {
            Mock Get-WatchdogTask {
                [PSCustomObject]@{
                    State = 'Disabled'
                }
            }

            Mock Get-WatchdogTaskInfo {
                [PSCustomObject]@{}
            }

            (Get-RdpWatchdogStatus).Status | Should -Be 'Stopped'
        }

        It 'Maps Unknown state to Stopped' {
            Mock Get-WatchdogTask {
                [PSCustomObject]@{
                    State = 'Queued'
                }
            }

            Mock Get-WatchdogTaskInfo {
                [PSCustomObject]@{}
            }

            (Get-RdpWatchdogStatus).Status | Should -Be 'Stopped'
        }
    }

    Context 'Task info edge cases' {

        BeforeEach {
            Mock Get-WatchdogTask {
                [PSCustomObject]@{
                    State = 'Ready'
                }
            }
        }

        It 'Handles null run times' {
            Mock Get-WatchdogTaskInfo {
                [PSCustomObject]@{
                    LastRunTime = $null
                    NextRunTime = $null
                }
            }

            $result = Get-RdpWatchdogStatus

            $result.LastRun | Should -BeNullOrEmpty
            $result.NextRun | Should -BeNullOrEmpty
        }

        It 'Handles missing LastRunTime' {
            Mock Get-WatchdogTaskInfo {
                [PSCustomObject]@{
                    NextRunTime = [datetime]'2026-01-02'
                }
            }

            { Get-RdpWatchdogStatus } | Should -Not -Throw
        }

        It 'Returns null LastRun when property is missing' {
            Mock Get-WatchdogTaskInfo {
                [PSCustomObject]@{
                    NextRunTime = [datetime]'2026-01-02'
                }
            }

            (Get-RdpWatchdogStatus).LastRun | Should -BeNullOrEmpty
        }

        It 'Handles missing NextRunTime' {
            Mock Get-WatchdogTaskInfo {
                [PSCustomObject]@{
                    LastRunTime = [datetime]'2026-01-01'
                }
            }

            { Get-RdpWatchdogStatus } | Should -Not -Throw
        }

        It 'Returns null NextRun when property is missing' {
            Mock Get-WatchdogTaskInfo {
                [PSCustomObject]@{
                    LastRunTime = [datetime]'2026-01-01'
                }
            }

            (Get-RdpWatchdogStatus).NextRun | Should -BeNullOrEmpty
        }

        It 'Handles null task info object' {
            Mock Get-WatchdogTaskInfo { $null }

            { Get-RdpWatchdogStatus } | Should -Not -Throw
        }

        It 'Returns null LastRun and NextRun when task info object is null' {
            Mock Get-WatchdogTaskInfo { $null }

            $result = Get-RdpWatchdogStatus

            $result.LastRun | Should -BeNullOrEmpty
            $result.NextRun | Should -BeNullOrEmpty
        }
    }

    Context 'Error handling' {

        It 'Handles Get-WatchdogTask failure' {
            Mock Get-WatchdogTask {
                throw 'Task Scheduler unavailable'
            }

            { Get-RdpWatchdogStatus } | Should -Throw
        }

        It 'Handles Get-WatchdogTaskInfo failure' {
            Mock Get-WatchdogTask {
                [PSCustomObject]@{
                    State = 'Ready'
                }
            }

            Mock Get-WatchdogTaskInfo {
                throw 'Failed'
            }

            { Get-RdpWatchdogStatus } | Should -Throw
        }
    }

    Context 'Return contract' {

        BeforeEach {
            Mock Get-WatchdogTask { $null }
        }

        It 'Returns exactly one object' {
            @(Get-RdpWatchdogStatus).Count | Should -Be 1
        }

        It 'Contains required properties' {
            $result = Get-RdpWatchdogStatus

            $result.PSObject.Properties.Name | Should -Contain 'Status'
            $result.PSObject.Properties.Name | Should -Contain 'LastRun'
            $result.PSObject.Properties.Name | Should -Contain 'NextRun'
            $result.PSObject.Properties.Name | Should -Contain 'CheckedAt'
        }

        It 'Returns CheckedAt in ISO8601 format' {
            (Get-RdpWatchdogStatus).CheckedAt |
                Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        }

        It 'Returns PSCustomObject' {
            (Get-RdpWatchdogStatus) | Should -BeOfType PSCustomObject
        }
    }
}
