#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Engine/New-WatchdogTaskAction.ps1"

    $script:ManifestPath = "$PSScriptRoot/../../../../RDPControl.psd1"
    $script:ModulePath   = 'C:\Modules\RDPControl'
}

Describe 'New-WatchdogTaskAction' {

    BeforeEach {
        Mock New-ScheduledTaskAction {
            [pscustomobject]@{
                Execute  = $Execute
                Argument = $Argument
            }
        }
    }

    Context 'Action creation' {

        It 'Runs Windows PowerShell' {
            $action = New-WatchdogTaskAction -ModulePath $script:ModulePath

            $action.Execute | Should -Be 'powershell.exe'
        }

        It 'Runs without a profile, non-interactively and hidden' {
            $action = New-WatchdogTaskAction -ModulePath $script:ModulePath

            $action.Argument | Should -Match '-NoProfile'
            $action.Argument | Should -Match '-NonInteractive'
            $action.Argument | Should -Match '-WindowStyle Hidden'
        }

        It 'Overrides the execution policy for the task process' {
            $action = New-WatchdogTaskAction -ModulePath $script:ModulePath

            $action.Argument | Should -Match '-ExecutionPolicy Bypass'
        }

        It 'Imports the module manifest from the given module path' {
            $action = New-WatchdogTaskAction -ModulePath $script:ModulePath

            $action.Argument | Should -BeLike "*Import-Module 'C:\Modules\RDPControl\RDPControl.psd1'*"
        }

        It 'Calls Invoke-RdpWatchdog with a literal -Confirm:$false' {
            $action = New-WatchdogTaskAction -ModulePath $script:ModulePath

            $action.Argument | Should -BeLike '*Invoke-RdpWatchdog -Confirm:$false*'
        }

        It 'Stops on the first error so failures surface in LastTaskResult' {
            $action = New-WatchdogTaskAction -ModulePath $script:ModulePath

            $action.Argument | Should -BeLike "*`$ErrorActionPreference = 'Stop'*"
        }
    }

    Context 'Command body references only exported commands' {

        It 'Uses Import-Module and manifest-exported functions only' {
            $action = New-WatchdogTaskAction -ModulePath $script:ModulePath

            $isCommandString = $action.Argument -match '-Command "(?<body>.+)"$'
            $isCommandString | Should -BeTrue

            $body   = $Matches['body']
            $tokens = $null
            $errors = $null
            $ast    = [System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$tokens, [ref]$errors)

            $errors | Should -BeNullOrEmpty

            $commands = @(
                $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
                    ForEach-Object -Process { $_.GetCommandName() }
            )

            $commands | Should -Not -BeNullOrEmpty
            $commands | Should -Contain 'Invoke-RdpWatchdog'

            $exported = (Import-PowerShellDataFile -Path $script:ManifestPath).FunctionsToExport
            $allowed  = @('Import-Module') + @($exported)

            foreach ($name in $commands) {
                $allowed | Should -Contain $name
            }
        }
    }

    Context 'Parameter validation' {

        It 'Requires a module path' {
            { New-WatchdogTaskAction -ModulePath '' } | Should -Throw
        }
    }

    Context 'Error handling' {

        It 'Propagates New-ScheduledTaskAction failures' {
            Mock New-ScheduledTaskAction { throw 'Action failure' }

            { New-WatchdogTaskAction -ModulePath $script:ModulePath } | Should -Throw
        }
    }
}
