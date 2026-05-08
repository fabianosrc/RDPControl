#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'PSScriptAnalyzer'; ModuleVersion = '1.25.0' }

<#
.SYNOPSIS
Runs PSScriptAnalyzer against the PipeDFe source code.

.DESCRIPTION
Analyzes all .ps1 and .psm1 files under the target path using the
project's PSScriptAnalyzerSettings.psd1 ruleset. Outputs a formatted
table and, optionally, writes a machine-readable SARIF report to
output/lint/ for CI consumption.

Exit codes:
    0 - no issues (or issues found but -Strict not set)
    1 - one or more issues found and -Strict is set

.PARAMETER Path
Path to analyze. Defaults to <repo-root>/src.

.PARAMETER Strict
Exits with code 1 if any warnings or errors are found.

.PARAMETER Severity
Severity levels to report. Defaults to Error and Warning.
Accepts: Error, Warning, Information.

.PARAMETER WriteSarif
Writes a SARIF 2.1 report to output/lint/results.sarif.json.
Useful for GitHub Code Scanning integration.

.EXAMPLE
PS C:\> .\tools\Invoke-Lint.ps1

.EXAMPLE
PS C:\> .\tools\Invoke-Lint.ps1 -Strict

.EXAMPLE
PS C:\> .\tools\Invoke-Lint.ps1 -Severity Error, Warning, Information -WriteSarif
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param (
    [Parameter()]
    [string]$Path,

    [Parameter()]
    [switch]$Strict,

    [Parameter()]
    [ValidateSet('Error', 'Warning', 'Information')]
    [string[]]$Severity = @('Error', 'Warning'),

    [Parameter()]
    [switch]$WriteSarif
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Paths
$root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
$resolvedPath = if ($PSBoundParameters.ContainsKey('Path')) { $Path } else { Join-Path -Path $root -ChildPath 'src' }
$settingsPath = Join-Path -Path $root -ChildPath 'PSScriptAnalyzerSettings.psd1'
$outputDir = Join-Path -Path $root -ChildPath 'output' -AdditionalChildPath 'lint'
#endregion

#region Banner
$analyzerVersion = (Get-Module -Name PSScriptAnalyzer -ListAvailable |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1).Version

Write-Host ''
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
Write-Host "  PipeDFe - Lint  (PSScriptAnalyzer $analyzerVersion)" -ForegroundColor Cyan
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
Write-Host ''
Write-Host "  Path     : $resolvedPath" -ForegroundColor Gray
Write-Host "  Severity : $($Severity -join ', ')" -ForegroundColor Gray
Write-Host "  Settings : $(if (Test-Path -LiteralPath $settingsPath) { $settingsPath } else { '(none)' })" -ForegroundColor Gray
Write-Host ''
#endregion

#region Analyze
$analyzerParams = @{
    Path     = $resolvedPath
    Recurse  = $true
    Severity = $Severity
}

if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    $analyzerParams['Settings'] = $settingsPath
}

$results = @(Invoke-ScriptAnalyzer @analyzerParams)
#endregion

#region Output
if ($results.Count -eq 0) {
    Write-Host '  ✔  No issues found.' -ForegroundColor Green
    Write-Host ''
} else {
    $errors = @($results | Where-Object Severity -eq 'Error')
    $warnings = @($results | Where-Object Severity -eq 'Warning')
    $infos = @($results | Where-Object Severity -eq 'Information')

    $results |
    Sort-Object -Property Severity, ScriptName, Line |
    Format-Table -AutoSize -Property @(
        @{
            Label      = 'Severity'
            Expression = {
                switch ($_.Severity) {
                    'Error' {
                        '✖ Error'
                    }
                    'Warning' {
                        '⚠ Warning'
                    }
                    'Information' {
                        'ℹ Info'
                    }
                }
            }
        },
        @{
            Label      = 'File'
            Expression = { Split-Path -Path $_.ScriptPath -Leaf }
        },
        @{
            Label      = 'Line'
            Expression = { $_.Line }
        },
        @{
            Label      = 'Rule'
            Expression = { $_.RuleName }
        },
        @{
            Label      = 'Message'
            Expression = { $_.Message }
        }
    )

    Write-Host ("  Errors      : {0}" -f $errors.Count)   -ForegroundColor $(if ($errors.Count) { 'Red' } else { 'Green' })
    Write-Host ("  Warnings    : {0}" -f $warnings.Count) -ForegroundColor $(if ($warnings.Count) { 'Yellow' } else { 'Green' })
    Write-Host ("  Information : {0}" -f $infos.Count)    -ForegroundColor Gray
    Write-Host ''
}
#endregion

#region SARIF report
if ($WriteSarif) {
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }

    $sarifPath = Join-Path -Path $outputDir -ChildPath 'results.sarif.json'

    $sarif = [ordered]@{
        '$schema' = 'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json'
        version   = '2.1.0'

        runs = @(
            [ordered]@{
                tool = [ordered]@{
                    driver = [ordered]@{
                        name    = 'PSScriptAnalyzer'
                        version = "$analyzerVersion"
                        rules   = @()
                    }
                }
                results = @(
                    $results | ForEach-Object {
                        [ordered]@{
                            ruleId = $_.RuleName
                            level  = switch ($_.Severity) {
                                'Error' {
                                    'error'
                                }
                                'Warning' {
                                    'warning'
                                }
                                default {
                                    'note'
                                }
                            }
                            message   = [ordered]@{ text = $_.Message }
                            locations = @(
                                [ordered]@{
                                    physicalLocation = [ordered]@{
                                        artifactLocation = [ordered]@{
                                            uri = ($_.ScriptPath -replace '\\', '/')
                                        }
                                        region = [ordered]@{
                                            startLine   = $_.Line
                                            startColumn = $_.Column
                                        }
                                    }
                                }
                            )
                        }
                    }
                )
            }
        )
    }

    $sarif | ConvertTo-Json -Depth 10 | Set-Content -Path $sarifPath -Encoding UTF8
    Write-Host "  SARIF report : $sarifPath" -ForegroundColor Gray
    Write-Host ''
}
#endregion

#region Footer
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
Write-Host ''
#endregion

#region Exit
if ($Strict -and $results.Count -gt 0) {
    exit 1
}
#endregion
