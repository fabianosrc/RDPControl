#Requires -Version 5.1

<#
.SYNOPSIS
Runs PSScriptAnalyzer against the RDPControl source code.

.DESCRIPTION
Analyzes all PowerShell files under the target path using the project's
PSScriptAnalyzerSettings.psd1 ruleset when available.

Outputs a formatted table for humans and, optionally, writes a
machine-readable SARIF 2.1.0 report to output/lint/results.sarif.json.

Exit codes:
    0 - no Error/Warning issues found
    1 - one or more Error/Warning issues found when -Strict is set

.PARAMETER Path
Path to analyze. Defaults to <repo-root>/src.

.PARAMETER Strict
Exits with code 1 if any Error or Warning is found.

.PARAMETER Severity
Severity levels to report.
Accepts: Error, Warning, Information.
Defaults to Error and Warning.

.PARAMETER WriteSarif
Writes a SARIF 2.1.0 report to output/lint/results.sarif.json.

.EXAMPLE
PS C:\> .\tools\Invoke-Lint.ps1

.EXAMPLE
PS C:\> .\tools\Invoke-Lint.ps1 -Strict

.EXAMPLE
PS C:\> .\tools\Invoke-Lint.ps1 -Severity Error, Warning, Information -WriteSarif

.EXAMPLE
PS C:\> .\tools\Invoke-Lint.ps1 -Path .\src -Strict -WriteSarif
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'This script intentionally provides console-oriented CLI output.'
)]
[CmdletBinding()]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
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
$root = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

$resolvedPath = if ($PSBoundParameters.ContainsKey('Path')) {
    $Path
} else {
    Join-Path -Path $root -ChildPath 'src'
}

$settingsPath = Join-Path -Path $root -ChildPath 'PSScriptAnalyzerSettings.psd1'
$outputDir    = Join-Path -Path $root -ChildPath 'output\lint'
$sarifPath    = Join-Path -Path $outputDir -ChildPath 'results.sarif.json'
#endregion

#region Helpers
function Write-Section {
    param (
        [Parameter(Mandatory)]
        [string]$Text
    )

    Write-Host ''
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
    Write-Host ''
}

function Get-SarifLevel {
    param (
        [Parameter(Mandatory)]
        [string]$Severity
    )

    switch ($Severity) {
        'Error'       { 'error' }
        'Warning'     { 'warning' }
        'Information' { 'note' }
        default       { 'none' }
    }
}

function Get-SarifFingerprint {
    param (
        [Parameter(Mandatory)]
        $Result
    )

    $input  = '{0}|{1}|{2}|{3}' -f $Result.RuleName, $Result.ScriptPath, $Result.Line, $Result.Column
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($input)
        $hash  = $sha256.ComputeHash($bytes)

        ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}
#endregion

#region Verify path
if (-not (Test-Path -LiteralPath $resolvedPath)) {
    Write-Host "  Path not found: $resolvedPath" -ForegroundColor Red
    exit 1
}

$resolvedPath = (Resolve-Path -LiteralPath $resolvedPath -ErrorAction Stop).Path

if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
    Write-Host "  Path is not a directory: $resolvedPath" -ForegroundColor Red
    exit 1
}
#endregion

#region Verify PSScriptAnalyzer
$requiredVersion  = $env:RDPCONTROL_ANALYZER_VERSION
$availableModules = @(
    Get-Module -Name PSScriptAnalyzer -ListAvailable -ErrorAction SilentlyContinue
)

if (-not [string]::IsNullOrWhiteSpace($requiredVersion)) {
    $analyzer = $availableModules |
        Where-Object { $_.Version -eq [version]$requiredVersion } |
        Select-Object -First 1
} else {
    $analyzer = $availableModules |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
}

if (-not $analyzer) {
    throw "PSScriptAnalyzer is not installed. Install it with: Install-Module PSScriptAnalyzer"
}

$importParams = @{
    Name            = 'PSScriptAnalyzer'
    RequiredVersion = $analyzer.Version.ToString()
    Force           = $true
    ErrorAction     = 'Stop'
}

Import-Module @importParams
#endregion

#region Banner
Write-Section "RDPControl - Lint  (PSScriptAnalyzer $($analyzer.Version))"

Write-Host "  Path     : $resolvedPath" -ForegroundColor Gray
Write-Host "  Severity : $($Severity -join ', ')" -ForegroundColor Gray

if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    Write-Host "  Settings : $settingsPath" -ForegroundColor Gray
} else {
    Write-Host '  Settings : (none)' -ForegroundColor DarkGray
}

Write-Host "  Strict   : $Strict" -ForegroundColor Gray
Write-Host "  SARIF    : $WriteSarif" -ForegroundColor Gray
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

try {
    $results = @(Invoke-ScriptAnalyzer @analyzerParams)
} catch {
    Write-Host ''
    Write-Host '  PSScriptAnalyzer failed:' -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    exit 1
}
#endregion

#region Results
$errors   = @($results | Where-Object { $_.Severity -eq 'Error' })
$warnings = @($results | Where-Object { $_.Severity -eq 'Warning' })
$infos    = @($results | Where-Object { $_.Severity -eq 'Information' })

if ($results.Count -eq 0) {
    Write-Host '  No issues found.' -ForegroundColor Green
    Write-Host ''
} else {
    $severityOrder = @{
        Error       = 0
        Warning     = 1
        Information = 2
    }

    $sortedResults = $results |
        Sort-Object -Property @(
            @{ Expression = {
                if ($severityOrder.ContainsKey($_.Severity)) { $severityOrder[$_.Severity] } else { 99 }
            } },
            @{ Expression = { $_.ScriptPath } },
            @{ Expression = { $_.Line } },
            @{ Expression = { $_.Column } },
            @{ Expression = { $_.RuleName } }
        )

    $sortedResults |
        Format-Table -AutoSize -Property @(
            @{
                Label      = 'Severity'
                Expression = {
                    switch ($_.Severity) {
                        'Error'       { 'Error' }
                        'Warning'     { 'Warning' }
                        'Information' { 'Info' }
                        default       { $_.Severity }
                    }
                }
            },
            @{
                Label      = 'File'
                Expression = {
                    try {
                        $relative = [System.IO.Path]::GetRelativePath($root, $_.ScriptPath)
                        if ([string]::IsNullOrWhiteSpace($relative)) { $_.ScriptPath } else { $relative }
                    } catch {
                        Split-Path -Path $_.ScriptPath -Leaf
                    }
                }
            },
            @{ Label = 'Line';    Expression = { $_.Line } },
            @{ Label = 'Column';  Expression = { $_.Column } },
            @{ Label = 'Rule';    Expression = { $_.RuleName } },
            @{ Label = 'Message'; Expression = { $_.Message } }
        )

    Write-Host ''

    $errorColor   = if ($errors.Count -gt 0)   { 'Red' }    else { 'Green' }
    $warningColor = if ($warnings.Count -gt 0)  { 'Yellow' } else { 'Green' }

    Write-Host ("  Errors      : {0}" -f $errors.Count)   -ForegroundColor $errorColor
    Write-Host ("  Warnings    : {0}" -f $warnings.Count) -ForegroundColor $warningColor
    Write-Host ("  Information : {0}" -f $infos.Count)    -ForegroundColor Gray
    Write-Host ''
}
#endregion

#region SARIF
if ($WriteSarif) {
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $sarifResults = @(
        $results | ForEach-Object {
            $relativePath = $_.ScriptPath

            try {
                $relativePath = [System.IO.Path]::GetRelativePath($root, $_.ScriptPath)
            } catch {
                $null = $_
            }

            $relativePath = $relativePath -replace '\\', '/'
            $artifactUri  = "file:///$($relativePath.TrimStart('/'))"

            [ordered]@{
                ruleId    = $_.RuleName
                level     = Get-SarifLevel -Severity $_.Severity
                message   = [ordered]@{ text = [string]$_.Message }
                locations = @(
                    [ordered]@{
                        physicalLocation = [ordered]@{
                            artifactLocation = [ordered]@{ uri = $artifactUri }
                            region           = [ordered]@{
                                startLine   = [int]$_.Line
                                startColumn = [int]$_.Column
                            }
                        }
                    }
                )
                partialFingerprints = [ordered]@{
                    primaryLocationLineHash = Get-SarifFingerprint -Result $_
                }
            }
        }
    )

    $ruleIds = @(
        $results |
            Where-Object { $_.RuleName } |
            Select-Object -ExpandProperty RuleName -Unique |
            Sort-Object
    )

    $sarifRules = @(
        $ruleIds | ForEach-Object {
            [ordered]@{
                id               = $_
                shortDescription = [ordered]@{ text = "PSScriptAnalyzer rule $_" }
                defaultConfiguration = [ordered]@{ level = 'warning' }
            }
        }
    )

    $sarif = [ordered]@{
        '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
        version   = '2.1.0'
        runs      = @(
            [ordered]@{
                tool = [ordered]@{
                    driver = [ordered]@{
                        name           = 'PSScriptAnalyzer'
                        version        = [string]$analyzer.Version
                        informationUri = 'https://github.com/PowerShell/PSScriptAnalyzer'
                        rules          = $sarifRules
                    }
                }
                results = $sarifResults
            }
        )
    }

    Set-Content -LiteralPath $sarifPath -Value ($sarif | ConvertTo-Json -Depth 20) -Encoding UTF8

    Write-Host "  SARIF report : $sarifPath" -ForegroundColor Gray
    Write-Host "  Findings     : $($results.Count)" -ForegroundColor Gray
    Write-Host ''
}
#endregion

#region Footer
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
Write-Host ''
#endregion

#region Exit
$blockingResults = @($results | Where-Object { $_.Severity -in @('Error', 'Warning') })

if ($Strict -and $blockingResults.Count -gt 0) {
    Write-Host ("  Lint failed: {0} Error/Warning issue(s)." -f $blockingResults.Count) -ForegroundColor Red
    Write-Host ''
    exit 1
}

if ($Strict) {
    Write-Host '  Strict lint passed.' -ForegroundColor Green
    Write-Host ''
}

exit 0
#endregion
