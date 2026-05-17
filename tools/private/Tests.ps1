<#
.SYNOPSIS
Runs the RDPControl Pester 5 test suite.

.DESCRIPTION
Discovers and executes all tests under the tests/ directory.

Features:
- Pester 5+
- NUnit/JUnit XML output
- JaCoCo coverage reports
- CI-friendly output
- Cross-version Pester compatibility
- Safe StrictMode support

Exit codes:
    0 - success
    1 - test failures
    2 - no tests discovered
    3 - invalid environment / dependencies

.PARAMETER Coverage
Enables code coverage collection.

.PARAMETER OutputFormat
Pester XML output format.

.PARAMETER TestPath
Custom test root path.

.PARAMETER Tag
Only run matching tags.

.PARAMETER ExcludeTag
Exclude matching tags.

.PARAMETER PassThru
Returns the Pester result object.

.EXAMPLE
PS> .\tools\private\Tests.ps1

.EXAMPLE
PS> .\tools\private\Tests.ps1 -Coverage

.EXAMPLE
PS> .\tools\private\Tests.ps1 -Tag Unit

.OUTPUTS
Pester.Run
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

#region Helpers

function Get-SafePropertyValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        $Default = $null
    )

    if ($null -eq $InputObject) {
        return $Default
    }

    if ($InputObject.PSObject.Properties[$Name]) {
        return $InputObject.$Name
    }

    return $Default
}

function Get-CollectionCount {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return 0
    }

    if (
        $InputObject -is [System.Collections.IEnumerable] -and
        $InputObject -isnot [string]
    ) {
        return @($InputObject).Count
    }

    return 1
}

function Write-Section {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Title
    )

    $divider = '------------------------------------------------'

    Write-Host ''
    Write-Host $divider -ForegroundColor DarkGray
    Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
    Write-Host $divider -ForegroundColor DarkGray
    Write-Host ''
}

function Resolve-RepoRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    return (Get-Item -Path (Join-Path $PSScriptRoot '../..')).FullName
}

function Get-CoverageSummary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$CoverageResult
    )

    $executed = Get-SafePropertyValue $CoverageResult 'CommandsExecuted'
    $missed   = Get-SafePropertyValue $CoverageResult 'CommandsMissed'
    $analyzed = Get-SafePropertyValue $CoverageResult 'CommandsAnalyzed'

    $hitCount   = Get-CollectionCount $executed
    $missCount  = Get-CollectionCount $missed
    $totalCount = Get-CollectionCount $analyzed

    if ($totalCount -eq 0) {
        $totalCount = $hitCount + $missCount
    }

    $pct = [double](
        Get-SafePropertyValue $CoverageResult 'CoveragePercent' -Default 0
    )

    if ($pct -eq 0 -and $totalCount -gt 0) {
        $pct = [Math]::Round(($hitCount / $totalCount) * 100, 1)
    }

    return [PSCustomObject][ordered]@{
        CoveragePercent = $pct
        CommandsTotal   = $totalCount
        CommandsHit     = $hitCount
        CommandsMissed  = $missCount
    }
}

#endregion

#region Validate Pester

$pesterModule = Get-Module -Name Pester -ListAvailable |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1

if ($null -eq $pesterModule) {
    Write-Error -Message (
        'Pester 5.0+ is not installed. ' +
        'Run: Install-Module Pester -Scope CurrentUser -Force'
    )
    exit 3
}

if ($pesterModule.Version -lt [Version]'5.0.0') {
    Write-Error -Message ("Pester 5.0+ required. Installed: {0}" -f $pesterModule.Version)
    exit 3
}

#endregion

#region Paths

$root        = Resolve-RepoRoot
$srcPath     = Join-Path $root 'src'
$outputPath  = Join-Path $root 'output'
$resultsDir  = Join-Path $outputPath 'test-results'
$coverageDir = Join-Path $outputPath 'coverage'

$resolvedTestPath = if ($PSBoundParameters.ContainsKey('TestPath')) {
    $TestPath
} else {
    Join-Path -Path $root -ChildPath 'tests'
}

if (-not (Test-Path -LiteralPath $resolvedTestPath -PathType Container)) {
    Write-Error -Message ("Test path not found: {0}" -f $resolvedTestPath)
    exit 2
}

foreach ($directory in @($resultsDir, $coverageDir)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

#endregion

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

Write-Section -Title ("Tests  (Pester {0})" -f $pesterModule.Version)

#region Pester configuration

$config = New-PesterConfiguration

$config.Run.Path     = $resolvedTestPath
$config.Run.PassThru = $true

$config.Output.Verbosity = if ($env:CI) {
    'Normal'
} else {
    'Detailed'
}

$config.TestResult.Enabled      = $true
$config.TestResult.OutputFormat = $OutputFormat
$config.TestResult.OutputPath   = Join-Path -Path $resultsDir (
    "TestResults.{0}.xml" -f $OutputFormat
)

if ($PSBoundParameters.ContainsKey('Tag') -and @($Tag).Count -gt 0) {
    $config.Filter.Tag = $Tag
}

if ($PSBoundParameters.ContainsKey('ExcludeTag') -and @($ExcludeTag).Count -gt 0) {
    $config.Filter.ExcludeTag = $ExcludeTag
}

#endregion

# ---------------------------------------------------------------------------
# Coverage configuration
# ---------------------------------------------------------------------------

if ($Coverage) {
    $coveredFiles = Get-ChildItem -Path $srcPath -Recurse -File -Filter '*.ps1' |
        Where-Object { $_.Name -notlike '*.Tests.ps1' } |
        Select-Object -ExpandProperty FullName

    if (@($coveredFiles).Count -eq 0) {
        Write-Warning ("No PowerShell source files found under '{0}'." -f $srcPath)
    }

    $config.CodeCoverage.Enabled               = $true
    $config.CodeCoverage.Path                  = $coveredFiles
    $config.CodeCoverage.OutputFormat          = 'JaCoCo'
    $config.CodeCoverage.CoveragePercentTarget = 80
    $config.CodeCoverage.OutputPath            = Join-Path $coverageDir 'coverage.xml'
}

# ---------------------------------------------------------------------------
# Execute tests
# ---------------------------------------------------------------------------

$timer = [System.Diagnostics.Stopwatch]::StartNew()
$result = Invoke-Pester -Configuration $config
$timer.Stop()

# ---------------------------------------------------------------------------
# Coverage summary
# ---------------------------------------------------------------------------

if ($Coverage) {
    $coverageResult = Get-SafePropertyValue $result 'CodeCoverage'

    if ($null -ne $coverageResult) {
        $summary = Get-CoverageSummary $coverageResult
        $pct     = [Math]::Round($summary.CoveragePercent, 1)

        $coverageColor = if ($pct -ge 80) {
            'Green'
        } elseif ($pct -ge 60) {
            'Yellow'
        } else {
            'Red'
        }

        Write-Section -Title 'Code Coverage'

        if ($summary.CommandsTotal -gt 0) {
            Write-Host (
                "  Overall : {0,6}%  ({1} / {2} commands)" -f
                    $pct,
                    $summary.CommandsHit,
                    $summary.CommandsTotal
            ) -ForegroundColor $coverageColor
        } else {
            Write-Host ("  Overall : {0,6}%" -f $pct) -ForegroundColor $coverageColor
        }

        $notExecuted = Get-SafePropertyValue $coverageResult 'CommandsNotExecuted'

        if ($null -ne $notExecuted -and @($notExecuted).Count -gt 0) {
            Write-Host ''
            Write-Host '  Missed by file:' -ForegroundColor DarkGray
            Write-Host ''

            $notExecuted |
                Group-Object { Split-Path -Path $_.File -Leaf } |
                Sort-Object -Property Count -Descending |
                ForEach-Object {
                    Write-Host (
                        "    {0,-45} {1,3} missed" -f $_.Name, $_.Count
                    ) -ForegroundColor Yellow
                }
        }

        Write-Host ''
        Write-Host (
            "  Report  : {0}" -f $config.CodeCoverage.OutputPath.Value
        ) -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------------------
# Test summary
# ---------------------------------------------------------------------------

$passedCount  = Get-SafePropertyValue $result 'PassedCount'  -Default 0
$failedCount  = Get-SafePropertyValue $result 'FailedCount'  -Default 0
$skippedCount = Get-SafePropertyValue $result 'SkippedCount' -Default 0
$totalCount   = Get-SafePropertyValue $result 'TotalCount'   -Default 0

$failedColor = if ($failedCount -eq 0) { 'Green' } else { 'Red' }

Write-Section -Title 'Test Summary'

Write-Host ("  Passed  : {0}" -f $passedCount)  -ForegroundColor Green
Write-Host ("  Failed  : {0}" -f $failedCount)  -ForegroundColor $failedColor
Write-Host ("  Skipped : {0}" -f $skippedCount) -ForegroundColor DarkGray
Write-Host ("  Total   : {0}" -f $totalCount)   -ForegroundColor Cyan
Write-Host ("  Time    : {0:n2}s" -f $timer.Elapsed.TotalSeconds) -ForegroundColor DarkGray

Write-Host ''
Write-Host ("  Results : {0}" -f $config.TestResult.OutputPath.Value) -ForegroundColor Gray

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------

if ($PassThru) { return $result }

if ($totalCount -eq 0) {
    Write-Warning 'No tests discovered. Verify test naming (*.Tests.ps1).'
    exit 2
}

if ($failedCount -gt 0) { exit 1 }

exit 0
