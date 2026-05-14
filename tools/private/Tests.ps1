<#
.SYNOPSIS
Runs the RDPControl test suite using Pester 5.

.DESCRIPTION
Discovers and executes all Pester tests under the tests/ directory.
Optionally collects code coverage and writes a JaCoCo-compatible XML
report to output/coverage/ for use in CI pipelines.

Exit codes:
    0 - all tests passed
    1 - one or more tests failed
    2 - no tests discovered

.PARAMETER Coverage
Enables code coverage collection.

.PARAMETER OutputFormat
Format for test results XML. Defaults to NUnitXml.

.PARAMETER TestPath
Path to test root. Defaults to <repo-root>/tests.

.PARAMETER Tag
Runs only tests with the specified Pester tag(s).

.PARAMETER ExcludeTag
Excludes tests with the specified Pester tag(s).

.PARAMETER PassThru
Returns the Pester result object instead of exiting.

.EXAMPLE
PS C:\> .\tools\private\Tests.ps1

.EXAMPLE
PS C:\> .\tools\private\Tests.ps1 -Coverage

.EXAMPLE
PS C:\> .\tools\private\Tests.ps1 -Coverage -Tag Unit

.OUTPUTS
Pester.Run - only when -PassThru is specified.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param (
    [Parameter()]
    [switch]$Coverage,

    [Parameter()]
    [ValidateSet('NUnitXml', 'JUnitXml')]
    [string]$OutputFormat = 'NUnitXml',

    [Parameter()]
    [string]$TestPath,

    [Parameter()]
    [string[]]$Tag,

    [Parameter()]
    [string[]]$ExcludeTag,

    [Parameter()]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -Name Pester -ListAvailable -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge '5.0.0' })) {
    Write-Warning -Message 'Pester 5.0+ is not installed. Run: Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force'
    exit 1
}

$root             = (Get-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).FullName
$srcPath          = Join-Path -Path $root -ChildPath 'src'
$outputPath       = Join-Path -Path $root -ChildPath 'output'
$resultsDir       = Join-Path -Path $outputPath -ChildPath 'test-results'
$coverageDir      = Join-Path -Path $outputPath -ChildPath 'coverage'
$resolvedTestPath = if ($PSBoundParameters.ContainsKey('TestPath')) { $TestPath } else { Join-Path -Path $root -ChildPath 'tests' }

if (-not (Test-Path -LiteralPath $resolvedTestPath -PathType Container)) {
    Write-Warning -Message "Test directory not found: $resolvedTestPath"
    exit 2
}

foreach ($dir in $resultsDir, $coverageDir) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

$pesterVersion = (Get-Module -Name Pester -ListAvailable |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1).Version

Write-Host ''
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host "  Tests  (Pester $pesterVersion)" -ForegroundColor Cyan
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''

$config = New-PesterConfiguration

$config.Run.Path                = $resolvedTestPath
$config.Run.PassThru            = $true
$config.Output.Verbosity        = 'Detailed'
$config.TestResult.Enabled      = $true
$config.TestResult.OutputPath   = Join-Path -Path $resultsDir -ChildPath "TestResults.$OutputFormat.xml"
$config.TestResult.OutputFormat = $OutputFormat

if ($PSBoundParameters.ContainsKey('Tag') -and $Tag.Count -gt 0) {
    $config.Filter.Tag = $Tag
}

if ($PSBoundParameters.ContainsKey('ExcludeTag') -and $ExcludeTag.Count -gt 0) {
    $config.Filter.ExcludeTag = $ExcludeTag
}

if ($Coverage) {
    $coveredFiles = Get-ChildItem -Path $srcPath -Filter '*.ps1' -Recurse |
        Select-Object -ExpandProperty FullName

    if ($coveredFiles.Count -eq 0) {
        Write-Warning -Message "No .ps1 files found under '$srcPath' - coverage will be empty."
    }

    $config.CodeCoverage.Enabled               = $true
    $config.CodeCoverage.Path                  = $coveredFiles
    $config.CodeCoverage.OutputPath            = Join-Path -Path $coverageDir -ChildPath 'coverage.xml'
    $config.CodeCoverage.OutputFormat          = 'JaCoCo'
    $config.CodeCoverage.CoveragePercentTarget = 80
}

$result = Invoke-Pester -Configuration $config

if ($Coverage -and $result.PSObject.Properties['CodeCoverage'] -and $null -ne $result.CodeCoverage) {
    $cc           = $result.CodeCoverage
    $totalCmds    = $cc.CommandsAnalyzed
    $executedCmds = $totalCmds - $cc.CommandsMissed
    $pct          = if ($totalCmds -gt 0) { [Math]::Round(($executedCmds / $totalCmds) * 100, 1) } else { 0 }
    $covColor     = if ($pct -ge 80) { 'Green' } elseif ($pct -ge 60) { 'Yellow' } else { 'Red' }

    Write-Host ''
    Write-Host '------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  Code Coverage' -ForegroundColor Cyan
    Write-Host '------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ("  Overall : {0,6}%  ({1} / {2} commands)" -f $pct, $executedCmds, $totalCmds) -ForegroundColor $covColor

    if ($cc.CommandsNotExecuted.Count -gt 0) {
        Write-Host ''
        Write-Host '  Missed by file:' -ForegroundColor DarkGray
        Write-Host ''

        $cc.CommandsNotExecuted |
            Group-Object -Property { Split-Path -Path $_.File -Leaf } |
            Sort-Object -Property Count -Descending |
            ForEach-Object {
                Write-Host ("    {0,-45} {1,3} missed" -f $_.Name, $_.Count) -ForegroundColor Yellow
            }
    }

    Write-Host ''
    Write-Host "  Report  : $($config.CodeCoverage.OutputPath.Value)" -ForegroundColor Gray
}

$failedCount  = if ($result.PSObject.Properties['FailedCount'])  { $result.FailedCount }  else { 0 }
$passedCount  = if ($result.PSObject.Properties['PassedCount'])  { $result.PassedCount }  else { 0 }
$skippedCount = if ($result.PSObject.Properties['SkippedCount']) { $result.SkippedCount } else { 0 }
$totalCount   = if ($result.PSObject.Properties['TotalCount'])   { $result.TotalCount }   else { 0 }
$duration     = if ($result.PSObject.Properties['Duration'])     { $result.Duration.TotalSeconds } else { 0 }

Write-Host ''
Write-Host '------------------------------------------------' -ForegroundColor DarkGray

$passColor = if ($failedCount -eq 0) { 'Green' } else { 'Red' }

Write-Host ("  Passed  : {0}" -f $passedCount)  -ForegroundColor Green
Write-Host ("  Failed  : {0}" -f $failedCount)  -ForegroundColor $passColor
Write-Host ("  Skipped : {0}" -f $skippedCount) -ForegroundColor DarkGray
Write-Host ("  Total   : {0}" -f $totalCount)   -ForegroundColor Cyan
Write-Host ("  Time    : {0:n2}s" -f $duration) -ForegroundColor DarkGray
Write-Host ''
Write-Host "  Results : $($config.TestResult.OutputPath.Value)" -ForegroundColor Gray
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''

if ($PassThru) {
    return $result
}

if ($totalCount -eq 0) {
    Write-Warning -Message 'No tests discovered. Check -TestPath and file naming (*.Tests.ps1).'
    exit 2
}

exit $(if ($failedCount -gt 0) { 1 } else { 0 })
