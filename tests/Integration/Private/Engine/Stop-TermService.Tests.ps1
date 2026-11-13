#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Integration tests for Stop-TermService and Start-TermService.

.DESCRIPTION
Verifies Stop-TermService and Start-TermService against the real
Windows TermService. No mocks are used.

These tests require Windows and an elevated PowerShell session.
When the required environment is unavailable, the suite is skipped.

The suite stops and restarts TermService. Active RDP sessions on the
machine running the tests will be disconnected.

Coverage includes:
  - Stop-TermService stops the service within the timeout.
  - Stop-TermService is idempotent when the service is already stopped.
  - Stop-TermService produces no pipeline output.
  - Start-TermService starts the service within the timeout.
  - Start-TermService is idempotent when the service is already running.
  - Start-TermService produces no pipeline output.
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

Describe 'Stop-TermService and Start-TermService' -Tag 'Integration' -Skip:$Script:SkipIntegration {

    InModuleScope -ModuleName RDPControl {

        AfterEach {

            $service = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue

            if ($null -ne $service -and $service.Status -ne 'Running') {
                Start-Service -Name 'TermService' -ErrorAction SilentlyContinue
            }
        }

        #region Stop-TermService
        Context 'Stop-TermService' {

            It 'Stops the service within the default timeout' {
                { Stop-TermService } | Should -Not -Throw

                $service = Get-Service -Name 'TermService' -ErrorAction Stop

                $service.Status | Should -Be 'Stopped'
            }

            It 'Is idempotent when the service is already stopped' {
                Stop-TermService

                { Stop-TermService } | Should -Not -Throw

                $service = Get-Service -Name 'TermService' -ErrorAction Stop

                $service.Status | Should -Be 'Stopped'
            }

            It 'Produces no pipeline output' {
                $result = @(Stop-TermService)

                $result | Should -HaveCount 0
            }
        }
        #endregion

        #region Start-TermService
        Context 'Start-TermService' {

            BeforeEach {

                Stop-Service -Name 'TermService' -Force -ErrorAction Stop
            }

            It 'Starts the service within the default timeout' {
                { Start-TermService } | Should -Not -Throw

                $service = Get-Service -Name 'TermService' -ErrorAction Stop

                $service.Status | Should -Be 'Running'
            }

            It 'Is idempotent when the service is already running' {
                Start-TermService

                { Start-TermService } | Should -Not -Throw

                $service = Get-Service -Name 'TermService' -ErrorAction Stop

                $service.Status | Should -Be 'Running'
            }

            It 'Produces no pipeline output' {
                $result = @(Start-TermService)

                $result | Should -HaveCount 0
            }
        }
        #endregion
    }
}
