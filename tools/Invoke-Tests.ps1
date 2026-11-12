#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Runs the RDPControl test suite using Pester 5 or 6.

.DESCRIPTION
Discovers and executes all Pester tests under the tests/ directory.
Optionally collects code coverage and writes a JaCoCo-compatible XML
report to output/coverage/ for use in CI pipelines.

When -Coverage is used, prints a detailed report of uncovered commands
grouped by file, including line numbers, so you know exactly what to
test next. Compatible with Pester 5.x and 6.x.

Exit codes:
    0 - all tests passed
    1 - one or more tests failed
    2 - test discovery returned no tests

.PARAMETER Coverage
Enables code coverage collection. Instruments all .ps1 files under src/.
Writes a JaCoCo XML report to output/coverage/coverage.xml.

.PARAMETER OutputFormat
Format for the test-results XML. Accepted values: NUnitXml, JUnitXml.
Defaults to NUnitXml.

.PARAMETER TestPath
Path to the test root. Defaults to <repo-root>/tests.

.PARAMETER Tag
Runs only tests with the specified Pester tag(s).

.PARAMETER ExcludeTag
Excludes tests with the specified Pester tag(s).

.PARAMETER CoverageTarget
Minimum coverage percentage to consider a success. Defaults to 80.

.PARAMETER ShowMissedLines
When -Coverage is active, prints the individual line numbers of every
uncovered command, in addition to the per-file summary.

.PARAMETER PassThru
Returns the Pester result object to the caller instead of exiting.

.EXAMPLE
PS C:\> .\tools\Invoke-Tests.ps1

.EXAMPLE
PS C:\> .\tools\Invoke-Tests.ps1 -Coverage

.EXAMPLE
PS C:\> .\tools\Invoke-Tests.ps1 -Coverage -ShowMissedLines

.EXAMPLE
PS C:\> .\tools\Invoke-Tests.ps1 -Coverage -CoverageTarget 95 -Tag Unit

.EXAMPLE
PS C:\> .\tools\Invoke-Tests.ps1 -PassThru | Select-Object -ExpandProperty FailedCount

.OUTPUTS
[Pester.Run] Only when -PassThru is specified.
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
    [switch]$DetailedOutput,

    [Parameter()]
    [string]$TestPath,

    [Parameter()]
    [string[]]$Tag = @(),

    [Parameter()]
    [string[]]$ExcludeTag = @(),

    [Parameter()]
    [ValidateRange(0, 100)]
    [double]$CoverageTarget = 80,

    [Parameter()]
    [switch]$ShowMissedLines,

    [Parameter()]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Helpers

<#
.SYNOPSIS
Safely unwraps a Pester option value whether it is a plain [string]
(Pester 6) or a [Pester.StringOption] object (Pester 5) that exposes
a .Value property.
#>
function Get-StringValue {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()]
        [object]$Option
    )

    if ($null -eq $Option) {
        return ''
    }

    if ($Option -is [string]) {
        return $Option
    }

    if ($Option.PSObject.Properties.Name -contains 'Value') {
        return $Option.Value
    }

    return $Option.ToString()
}

<#
.SYNOPSIS
Returns the list of commands not executed, regardless of Pester version.

Probes the actual properties present on the CodeCoverage object rather
than branching on version number. This is safer under StrictMode and
resilient to naming changes across Pester releases.

Known property names by version:
  Pester 5 : CommandsMissed
  Pester 6 : MissedCommands
  Legacy   : CommandsNotExecuted
#>
function Get-MissedCommand {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param (
        [Parameter()]
        [object]$CodeCoverage
    )

    $props = $CodeCoverage.PSObject.Properties.Name

    if ($props -contains 'CommandsMissed') {
        return $CodeCoverage.CommandsMissed
    }

    if ($props -contains 'MissedCommands') {
        return $CodeCoverage.MissedCommands
    }

    if ($props -contains 'CommandsNotExecuted') {
        return $CodeCoverage.CommandsNotExecuted
    }

    return @()
}

#endregion

#region Resolve paths

$root        = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$srcPath     = Join-Path -Path $root -ChildPath 'src'
$outputPath  = Join-Path -Path $root -ChildPath 'output'
$resultsDir  = Join-Path -Path $outputPath -ChildPath 'test-results'
$coverageDir = Join-Path -Path $outputPath -ChildPath 'coverage'

$resolvedTestPath = if ($PSBoundParameters.ContainsKey('TestPath')) {
    $TestPath
} else {
    Join-Path -Path $root -ChildPath 'tests'
}

if (-not (Test-Path -LiteralPath $resolvedTestPath -PathType Container)) {
    Write-Error "Test directory not found: $resolvedTestPath"
    exit 2
}

foreach ($dir in $resultsDir, $coverageDir) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

#endregion

#region Banner

$requiredVersion = $env:RDPCONTROL_PESTER_VERSION

$importParams = @{
    Name        = 'Pester'
    Force       = $true
    ErrorAction = 'Stop'
}

if (-not [string]::IsNullOrWhiteSpace($requiredVersion)) {
    $importParams.RequiredVersion = $requiredVersion
} else {
    $importParams.MinimumVersion = '5.0.0'
}

Import-Module @importParams

$pesterVersion = (Get-Module -Name Pester).Version

Write-Host ''
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
Write-Host "  RDPControl - Test Runner  (Pester $pesterVersion)" -ForegroundColor Cyan
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
Write-Host ''

#endregion

#region Pester configuration

$config = New-PesterConfiguration

$config.Run.Path                = $resolvedTestPath
$config.Run.PassThru            = $true
$config.Output.Verbosity        = if ($DetailedOutput) { 'Detailed' } else { 'Normal' }
$config.TestResult.Enabled      = $true
$config.TestResult.OutputPath   = Join-Path -Path $resultsDir -ChildPath "TestResults.$OutputFormat.xml"
$config.TestResult.OutputFormat = $OutputFormat

if ($Tag.Count -gt 0) {
    $config.Filter.Tag = $Tag
}

if ($ExcludeTag.Count -gt 0) {
    $config.Filter.ExcludeTag = $ExcludeTag
}

if ($Coverage) {
    $coveredFiles = Get-ChildItem -Path $srcPath -Filter '*.ps1' -Recurse |
        Select-Object -ExpandProperty FullName

    if ($coveredFiles.Count -eq 0) {
        Write-Warning "No .ps1 files found under '$srcPath' — coverage will be empty."
    }

    $config.CodeCoverage.Enabled               = $true
    $config.CodeCoverage.Path                  = $coveredFiles
    $config.CodeCoverage.OutputPath            = Join-Path -Path $coverageDir -ChildPath 'coverage.xml'
    $config.CodeCoverage.OutputFormat          = 'JaCoCo'
    $config.CodeCoverage.CoveragePercentTarget = $CoverageTarget
}

#endregion

#region Run

$result = Invoke-Pester -Configuration $config

#endregion

$coveragePercent = $null

#region Coverage report

if ($Coverage -and $null -ne $result.CodeCoverage) {
    $cc      = $result.CodeCoverage
    $pct     = 0.0
    $ccProps = $cc.PSObject.Properties.Name

    if ($ccProps -contains 'CoveragePercent' -and $cc.CoveragePercent -gt 0) {
        $pct = [System.Math]::Round([double]$cc.CoveragePercent, 2)
    } else {
        $totalCmds = if ($ccProps -contains 'CommandsAnalyzed') {
            [int]$cc.CommandsAnalyzed
        } else {
            0
        }

        $missedCmds = if ($ccProps -contains 'CommandsMissed') {
            [int]$cc.CommandsMissed
        } else {
            0
        }

        if ($totalCmds -gt 0) {
            $pct = [System.Math]::Round((($totalCmds - $missedCmds) / $totalCmds) * 100, 2)
        }
    }

    $coveragePercent = $pct

    $coverageColor = if ($pct -ge $CoverageTarget) {
        'Green'
    } elseif ($pct -ge 60) {
        'Yellow'
    } else {
        'Red'
    }

    $missed = Get-MissedCommand -CodeCoverage $cc

    Write-Host ''
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
    Write-Host '  Code Coverage' -ForegroundColor Cyan
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ("  Overall  : {0,6}%  (target: {1}%)" -f $pct, $CoverageTarget) -ForegroundColor $coverageColor

    if ($null -ne $missed -and $missed.Count -gt 0) {
        $byFile = $missed | Group-Object -Property { $_.File } | Sort-Object Count -Descending

        Write-Host ''
        Write-Host ("  {0} uncovered command(s) across {1} file(s):" -f $missed.Count, $byFile.Count) -ForegroundColor Yellow
        Write-Host ''

        foreach ($fileGroup in $byFile) {
            $fileName   = Split-Path -Leaf $fileGroup.Name
            $fileLabel  = "    - $fileName"
            $countLabel = ("{0,3} missed" -f $fileGroup.Count)

            Write-Host "$fileLabel" -NoNewline -ForegroundColor Yellow
            Write-Host (' ' * [Math]::Max(1, 48 - $fileLabel.Length)) -NoNewline
            Write-Host $countLabel -ForegroundColor Red

            if ($ShowMissedLines) {
                $lines = $fileGroup.Group |
                    Sort-Object -Property StartLine |
                    Select-Object -Property StartLine,
                    @{
                        Name       = 'Text'
                        Expression = {
                            if ($_.PSObject.Properties.Name -contains 'Command') {
                                ($_.Command -replace '\s+', ' ').Trim()
                            } elseif ($_.PSObject.Properties.Name -contains 'Text') {
                                ($_.Text -replace '\s+', ' ').Trim()
                            } else {
                                ''
                            }
                        }
                    }

                foreach ($line in $lines) {
                    $lineNum = if ($null -ne $line.StartLine) {
                        $line.StartLine
                    } else {
                        '?'
                    }

                    $lineText = if ($line.Text.Length -gt 60) {
                        $line.Text.Substring(0, 57) + '...'
                    } else {
                        $line.Text
                    }

                    Write-Host ("      Line {0,-6} {1}" -f $lineNum, $lineText) -ForegroundColor DarkYellow
                }

                Write-Host ''
            }
        }

        if (-not $ShowMissedLines) {
            Write-Host ''
            Write-Host '  Tip: run with -ShowMissedLines to see exact line numbers.' -ForegroundColor DarkGray
        }
    } else {
        Write-Host ''
        Write-Host '  All commands covered.' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host "  Report   : $(Get-StringValue $config.CodeCoverage.OutputPath)" -ForegroundColor Gray
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
    Write-Host ''
}

#endregion

#region Test results summary

Write-Host ''
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
Write-Host '  Test Results' -ForegroundColor Cyan
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray

$passColor = if ($result.FailedCount -eq 0) { 'Green' } else { 'Red' }

Write-Host ("  Passed   : {0}" -f $result.PassedCount)  -ForegroundColor Green
Write-Host ("  Failed   : {0}" -f $result.FailedCount)  -ForegroundColor $passColor
Write-Host ("  Skipped  : {0}" -f $result.SkippedCount) -ForegroundColor DarkGray
Write-Host ("  Total    : {0}" -f $result.TotalCount)   -ForegroundColor Cyan
Write-Host ("  Duration : {0:n2}s" -f $result.Duration.TotalSeconds) -ForegroundColor DarkGray
Write-Host ''
Write-Host "  Results  : $(Get-StringValue $config.TestResult.OutputPath)" -ForegroundColor Gray
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
Write-Host ''

#endregion

#region GitHub Actions summary

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    $coverageSummary = 'Not requested'

    if ($Coverage) {
        $coverageSummary = if ($null -ne $coveragePercent) {
            '{0}% (target: {1}%)' -f $coveragePercent, $CoverageTarget
        } else {
            'Unavailable'
        }
    }

    $summary = @(
        '## RDPControl - Test Results'
        ''
        '| Metric | Value |'
        '| --- | ---: |'
        ('| PowerShell | {0} |' -f $PSVersionTable.PSVersion)
        ('| Pester | {0} |' -f $pesterVersion)
        ('| Passed | {0} |' -f $result.PassedCount)
        ('| Failed | {0} |' -f $result.FailedCount)
        ('| Skipped | {0} |' -f $result.SkippedCount)
        ('| Total | {0} |' -f $result.TotalCount)
        ('| Duration | {0:N2}s |' -f $result.Duration.TotalSeconds)
        ('| Coverage | {0} |' -f $coverageSummary)
        ''
    )

    $summaryParams = @{
        LiteralPath = $env:GITHUB_STEP_SUMMARY
        Value       = $summary
        Encoding    = 'UTF8'
        ErrorAction = 'Stop'
    }

    try {
        Add-Content @summaryParams
    } catch {
        Write-Warning "Unable to write GitHub Actions summary: $($_.Exception.Message)"
    }
}

#endregion

#region Exit

if ($PassThru) {
    return $result
}

if ($result.TotalCount -eq 0) {
    Write-Warning 'No tests were discovered.'
    exit 2
}

if ($result.FailedCount -gt 0) {
    exit 1
}

if ($Coverage) {
    if ($null -eq $coveragePercent) {
        Write-Warning 'Code coverage results are unavailable.'
        exit 1
    }

    if ($coveragePercent -lt $CoverageTarget) {
        Write-Warning (
            'Code coverage {0}% is below the required {1}%.' -f
            $coveragePercent, $CoverageTarget
        )
        exit 1
    }
}

exit 0

#endregion
