<#
.SYNOPSIS
Runs PSScriptAnalyzer against the RDPControl source code.

.DESCRIPTION
Analyzes all .ps1 and .psm1 files under the target path using the
project PSScriptAnalyzerSettings.psd1 ruleset. Outputs a formatted
table and optionally writes a machine-readable SARIF report.

Exit codes:
    0 - no issues found (or -Strict not set)
    1 - issues found and -Strict is set

.PARAMETER Path
Path to analyze. Defaults to <repo-root>/src.

.PARAMETER Strict
Exits with code 1 if any warnings or errors are found.

.PARAMETER Severity
Severity levels to report. Defaults to Error and Warning.

.PARAMETER WriteSarif
Writes a SARIF 2.1 report to output/lint/results.sarif.json.

.EXAMPLE
PS C:\> .\tools\private\Lint.ps1

.EXAMPLE
PS C:\> .\tools\private\Lint.ps1 -Strict

.EXAMPLE
PS C:\> .\tools\private\Lint.ps1 -Severity Error, Warning, Information -WriteSarif
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param (
    [Parameter()]
    [string]$Path,

    [Parameter()]
    [switch]$Strict,

    [ValidateSet('Error', 'Warning', 'Information')]
    [string[]]$Severity = @('Error', 'Warning'),

    [Parameter()]
    [switch]$WriteSarif
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Get-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).FullName
$resolvedPath = if ($PSBoundParameters.ContainsKey('Path')) { $Path } else { Join-Path -Path $root -ChildPath 'src' }
$settingsPath = Join-Path -Path $root -ChildPath 'PSScriptAnalyzerSettings.psd1'
$outputDir = Join-Path -Path $root -ChildPath 'output\lint'

if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable -ErrorAction SilentlyContinue)) {
    Write-Warning -Message 'PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Scope CurrentUser'
    exit 1
}

$analyzerVersion = (Get-Module -Name PSScriptAnalyzer -ListAvailable |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1).Version

Write-Host ""
Write-Host "------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Lint  (PSScriptAnalyzer $analyzerVersion)" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Path     : $resolvedPath" -ForegroundColor Gray
Write-Host "  Severity : $($Severity -join ', ')" -ForegroundColor Gray
Write-Host "  Settings : $(if (Test-Path -LiteralPath $settingsPath) { $settingsPath } else { '(none)' })" -ForegroundColor Gray
Write-Host ""

$analyzerParams = @{
    Path     = $resolvedPath
    Recurse  = $true
    Severity = $Severity
}

if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    $analyzerParams['Settings'] = $settingsPath
}

$results = @(Invoke-ScriptAnalyzer @analyzerParams)

if ($results.Count -eq 0) {
    Write-Host '  No issues found.' -ForegroundColor Green
    Write-Host ''
} else {
    $errors = @($results | Where-Object -FilterScript { $_.Severity -eq 'Error' })
    $warnings = @($results | Where-Object -FilterScript { $_.Severity -eq 'Warning' })
    $infos = @($results | Where-Object -FilterScript { $_.Severity -eq 'Information' })

    $results |
    Sort-Object -Property Severity, ScriptName, Line |
    Format-Table -AutoSize -Property @(
        @{
            Label      = 'Severity'
            Expression = {
                switch ($_.Severity) {
                    'Error' { 'ERROR' }
                    'Warning' { 'WARN ' }
                    'Information' { 'INFO ' }
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
    Write-Host ""
}

if ($WriteSarif) {
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }

    $sarifPath = Join-Path -Path $outputDir -ChildPath 'results.sarif.json'

    $sarif = [ordered]@{
        '$schema' = 'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json'
        version   = '2.1.0'
        runs      = @(
            [ordered]@{
                tool    = [ordered]@{
                    driver = [ordered]@{
                        name    = 'PSScriptAnalyzer'
                        version = "$analyzerVersion"
                        rules   = @()
                    }
                }
                results = @(
                    $results | ForEach-Object {
                        [ordered]@{
                            ruleId    = $_.RuleName
                            level     = switch ($_.Severity) {
                                'Error' { 'error' }
                                'Warning' { 'warning' }
                                default { 'note' }
                            }
                            message   = [ordered]@{ text = $_.Message }
                            locations = @(
                                [ordered]@{
                                    physicalLocation = [ordered]@{
                                        artifactLocation = [ordered]@{ uri = ($_.ScriptPath -replace '\\', '/') }
                                        region           = [ordered]@{ startLine = $_.Line; startColumn = $_.Column }
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
    Write-Host ""
}

Write-Host "------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

if ($Strict -and $results.Count -gt 0) {
    exit 1
}
