#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Engine/New-WatchdogTaskTrigger.ps1"
}

Describe 'New-WatchdogTaskTrigger' {

    BeforeEach {
        Mock New-ScheduledTaskTrigger { [pscustomobject]@{ Delay = $null } }
    }

    Context 'Trigger creation' {

        It 'Creates an at-startup trigger' {
            New-WatchdogTaskTrigger | Out-Null

            Should -Invoke New-ScheduledTaskTrigger -Times 1 -ParameterFilter {
                $AtStartup -eq $true
            }
        }

        It 'Applies a 30 second delay by default' {
            $trigger = New-WatchdogTaskTrigger

            $trigger.Delay | Should -Be 'PT30S'
        }

        It 'Applies a custom delay' {
            $trigger = New-WatchdogTaskTrigger -Delay 'PT5M'

            $trigger.Delay | Should -Be 'PT5M'
        }
    }

    Context 'Parameter validation' {

        It 'Rejects a delay that is not an ISO 8601 duration' {
            { New-WatchdogTaskTrigger -Delay '5 minutes' } | Should -Throw
        }
    }

    Context 'Error handling' {

        It 'Propagates New-ScheduledTaskTrigger failures' {
            Mock New-ScheduledTaskTrigger { throw 'Trigger failure' }

            { New-WatchdogTaskTrigger } | Should -Throw
        }
    }
}
