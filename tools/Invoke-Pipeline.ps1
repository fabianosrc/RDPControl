<#
.SYNOPSIS
Orchestrates the full RDPControl development and release pipeline.

.DESCRIPTION
Runs the complete pipeline in order:

    1. Lint      - PSScriptAnalyzer (skippable with -SkipLint)
    2. Validate  - function names, exports, coding standards (skippable with -SkipValidation)
    3. Test      - Pester with optional coverage (skippable with -SkipTests)
    4. Build     - copies source into output/RDPControl/<version>/ (skippable with -SkipBuild)
    5. Import    - reimports the module (opt-in with -ImportAfterBuild)
    6. Manifest  - validates .psd1 required fields
    7. Publish   - Publish-Module to PSGallery (opt-in with -Publish)

Exit codes:
    0 - pipeline succeeded
    1 - one or more steps failed

.PARAMETER SkipLint
Skips the PSScriptAnalyzer step.

.PARAMETER SkipValidation
Skips the function name and export validation step.

.PARAMETER SkipTests
Skips the Pester test run.
Note: -Publish is blocked when -SkipTests is active. 80% coverage is
required before publishing to the PowerShell Gallery.

.PARAMETER SkipBuild
Skips the build step. Steps that depend on build output (Import, Manifest,
Publish) are automatically skipped when -SkipBuild is active.

.PARAMETER NoCoverage
Skips code coverage collection during tests.

.PARAMETER ImportAfterBuild
Reimports the module from source after a successful build.
Ignored when -SkipBuild is active.

.PARAMETER DevImport
Reimports the module directly from source without building.
Useful for rapid development iteration. Can be combined with -SkipBuild and -SkipTests.

.PARAMETER Publish
Publishes the built module to the PowerShell Gallery.
Requires the PSGALLERY_API_KEY environment variable.
Blocked when -SkipTests is active.

.EXAMPLE
PS C:\> .\tools\Invoke-Pipeline.ps1

Runs the full pipeline.

.EXAMPLE
PS C:\> .\tools\Invoke-Pipeline.ps1 -SkipBuild

Runs lint, validation, and tests only. Useful during active development.

.EXAMPLE
PS C:\> .\tools\Invoke-Pipeline.ps1 -SkipTests -ImportAfterBuild

Skips tests and reimports the module after build.

.EXAMPLE
PS C:\> .\tools\Invoke-Pipeline.ps1 -SkipTests -SkipBuild -DevImport

Skips tests and build, reimports the module directly from source.

.EXAMPLE
PS C:\> .\tools\Invoke-Pipeline.ps1 -Publish
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param (
    [Parameter()]
    [switch]$SkipLint,

    [Parameter()]
    [switch]$SkipValidation,

    [Parameter()]
    [switch]$SkipTests,

    [Parameter()]
    [switch]$SkipBuild,

    [Parameter()]
    [switch]$NoCoverage,

    [Parameter()]
    [switch]$ImportAfterBuild,

    [Parameter()]
    [switch]$DevImport,

    [Parameter()]
    [switch]$Publish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$LASTEXITCODE = 0

# -- Paths --------------------------------------------------------------------

$root         = (Get-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).FullName
$privateTools = Join-Path -Path $PSScriptRoot -ChildPath 'private'
$srcPath      = Join-Path -Path $root -ChildPath 'src'
$manifestPath = Join-Path -Path $root -ChildPath 'RDPControl.psd1'
$outputPath   = Join-Path -Path $root -ChildPath 'output'

# -- Guard: cannot publish without tests --------------------------------------

if ($Publish -and $SkipTests) {
    Write-Error -Message '[Pipeline] Cannot publish with -SkipTests. 80% coverage is required before publishing to the PowerShell Gallery.'
    exit 1
}

# -- Resolve downstream skip flags --------------------------------------------

if ($SkipBuild -and $ImportAfterBuild) {
    Write-Warning -Message '[Pipeline] -ImportAfterBuild ignored because -SkipBuild is active.'
}

if ($SkipBuild -and $Publish) {
    Write-Warning -Message '[Pipeline] -Publish ignored because -SkipBuild is active.'
}

# -- Helpers ------------------------------------------------------------------

function Write-PipelineBanner {
    param([string]$Version)
    Write-Host ''
    Write-Host '------------------------------------------------' -ForegroundColor DarkGray
    Write-Host "  RDPControl Pipeline  v$Version" -ForegroundColor Cyan
    Write-Host '------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ''
}

function Write-PipelineStep {
    param([int]$Index, [int]$Total, [string]$Label)
    Write-Host ''
    Write-Host "  [$Index/$Total] $Label" -ForegroundColor Cyan
    Write-Host ''
}

function Write-PipelineStepSkipped {
    param([int]$Index, [int]$Total, [string]$Label, [string]$Reason = '')
    $suffix = if ($Reason) { " ($Reason)" } else { '' }
    Write-Host "  [$Index/$Total] $Label - skipped$suffix" -ForegroundColor DarkGray
}

function Write-PipelineResult {
    param([bool]$Success, [string]$Message)
    $color = if ($Success) { 'Green' } else { 'Red' }
    $icon  = if ($Success) { 'OK  ' } else { 'FAIL' }
    Write-Host "  $icon  $Message" -ForegroundColor $color
}

function Stop-Pipeline {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param([string]$Reason)
    Write-Host ''
    Write-Host "  [ABORTED] $Reason" -ForegroundColor Red
    Write-Host ''
    exit 1
}

# -- Banner -------------------------------------------------------------------

$manifest = Import-PowerShellDataFile -Path $manifestPath
$version  = $manifest.ModuleVersion

$totalSteps = 0 +
    [int](-not $SkipLint.IsPresent) +
    [int](-not $SkipValidation.IsPresent) +
    [int](-not $SkipTests.IsPresent) +
    [int](-not $SkipBuild.IsPresent) +
    [int]($ImportAfterBuild -and -not $SkipBuild.IsPresent) +
    [int]$DevImport.IsPresent +
    [int](-not $SkipBuild.IsPresent) +
    [int]($Publish -and -not $SkipBuild.IsPresent)

$step = 0

Write-PipelineBanner -Version $version

# -- Step: Lint ---------------------------------------------------------------

$step++

if ($SkipLint) {
    Write-PipelineStepSkipped -Index $step -Total $totalSteps -Label 'Lint (PSScriptAnalyzer)'
} else {
    Write-PipelineStep -Index $step -Total $totalSteps -Label 'Lint (PSScriptAnalyzer)'

    $LASTEXITCODE = 0
    & (Join-Path -Path $privateTools -ChildPath 'Lint.ps1') -Strict

    if ($LASTEXITCODE -ne 0) {
        Stop-Pipeline -Reason 'Lint failed.'
    }

    Write-PipelineResult -Success $true -Message 'PSScriptAnalyzer clean.'
}

# -- Step: Validate -----------------------------------------------------------

$step++

if ($SkipValidation) {
    Write-PipelineStepSkipped -Index $step -Total $totalSteps -Label 'Validation'
} else {
    Write-PipelineStep -Index $step -Total $totalSteps -Label 'Validation'

    $validationErrors = [System.Collections.Generic.List[string]]::new()

    $exportedFunctions = $manifest.FunctionsToExport
    $publicPath        = Join-Path -Path $srcPath -ChildPath 'Public'
    $privatePath       = Join-Path -Path $srcPath -ChildPath 'Private'

    $publicFiles   = Get-ChildItem -Path $publicPath  -Filter '*.ps1' -Recurse | Select-Object -ExpandProperty BaseName
    $publicPsFiles = Get-ChildItem -Path $publicPath  -Filter '*.ps1' -Recurse
    $privateFiles  = Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse

    # 1. Exported function names must follow Verb-RdpNoun convention
    foreach ($fn in $exportedFunctions) {
        if ($fn -notmatch '^(Get|Set|New|Remove|Add|Start|Stop|Save|Restore|Invoke|Connect|Disconnect|Test|Initialize)-Rdp') {
            $validationErrors.Add("Invalid function name (missing Rdp prefix or wrong verb): $fn")
        }
    }

    # 2. Every exported function must have a matching .ps1 file in Public/
    foreach ($fn in $exportedFunctions) {
        if ($fn -notin $publicFiles) {
            $validationErrors.Add("Exported function has no matching .ps1 file: $fn")
        }
    }

    # 3. Every public .ps1 file must define a function matching the file name
    foreach ($file in $publicPsFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        if ($content -notmatch "function\s+$($file.BaseName)\b") {
            $validationErrors.Add("File [$($file.Name)] does not define function [$($file.BaseName)]")
        }
    }

    # 4. Every public .ps1 file must have .SYNOPSIS
    foreach ($file in $publicPsFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        if ($content -notmatch '\.SYNOPSIS') {
            $validationErrors.Add("Missing .SYNOPSIS in public file: $($file.Name)")
        }
    }

    # 5. Every public .ps1 file must be in FunctionsToExport
    $unexported = $publicFiles | Where-Object -FilterScript { $_ -notin $exportedFunctions }
    foreach ($fn in $unexported) {
        $validationErrors.Add("Public .ps1 file not in FunctionsToExport: $fn")
    }

    # 6. Prohibited terms in public file code lines (comments excluded)
    $prohibitedTerms = @('patch', 'bypass', 'crack', 'hack', 'tamper', 'unlock')
    foreach ($file in $publicPsFiles) {
        $codeLines = (Get-Content -LiteralPath $file.FullName) |
            Where-Object -FilterScript { $_ -notmatch '^\s*#' }
        $code = $codeLines -join ' '
        foreach ($term in $prohibitedTerms) {
            if ($code -imatch "\b$term\b") {
                $validationErrors.Add("Prohibited term '$term' found in public file: $($file.Name)")
            }
        }
    }

    # 7. No Write-Host in private functions
    foreach ($file in $privateFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        if ($content -match '\bWrite-Host\b') {
            $validationErrors.Add("Write-Host found in private file: $($file.Name)")
        }
    }

    # 8. No #Requires in src files
    foreach ($file in ($publicPsFiles + $privateFiles)) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        if ($content -match '#Requires') {
            $validationErrors.Add("#Requires found in src file: $($file.Name)")
        }
    }

    # 9. No em-dashes in src files
    foreach ($file in ($publicPsFiles + $privateFiles)) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        if ($content -match [char]0x2014) {
            $validationErrors.Add("Em-dash found in: $($file.Name)")
        }
    }

    if ($validationErrors.Count -gt 0) {
        Write-Host ''
        Write-Host "  $($validationErrors.Count) validation error(s):" -ForegroundColor Red
        Write-Host ''

        foreach ($err in $validationErrors) {
            Write-Host "    - $err" -ForegroundColor Yellow
        }

        Stop-Pipeline -Reason 'Validation failed. Fix all issues before continuing.'
    }

    Write-PipelineResult -Success $true -Message (
        "Validation passed. " +
        "$($exportedFunctions.Count) exported, " +
        "$($publicFiles.Count) public files, " +
        "$($privateFiles.Count) private files."
    )
}

# -- Step: Test ---------------------------------------------------------------

$step++

if ($SkipTests) {
    Write-PipelineStepSkipped -Index $step -Total $totalSteps -Label 'Tests (Pester)'
    Write-Host '  WARN  Tests skipped. 80% coverage required before publishing to Gallery.' -ForegroundColor Yellow
} else {
    Write-PipelineStep -Index $step -Total $totalSteps -Label 'Tests (Pester)'

    $testArgs = @{}
    if (-not $NoCoverage) { $testArgs['Coverage'] = $true }

    $LASTEXITCODE = 0
    & (Join-Path -Path $privateTools -ChildPath 'Tests.ps1') @testArgs

    if ($LASTEXITCODE -ne 0) {
        Stop-Pipeline -Reason 'Tests failed. All tests must pass before building.'
    }

    Write-PipelineResult -Success $true -Message 'All tests passed.'
}

# -- Step: Build --------------------------------------------------------------

$step++

if ($SkipBuild) {
    Write-PipelineStepSkipped -Index $step -Total $totalSteps -Label 'Build' -Reason 'import, manifest validation, and publish also skipped'
} else {
    Write-PipelineStep -Index $step -Total $totalSteps -Label 'Build'

    $LASTEXITCODE = 0
    & (Join-Path -Path $privateTools -ChildPath 'Build.ps1') -SkipLint -SkipTests

    if ($LASTEXITCODE -ne 0) {
        Stop-Pipeline -Reason 'Build failed.'
    }

    $dest = Join-Path -Path $outputPath -ChildPath "RDPControl\$version"
    Write-PipelineResult -Success $true -Message "Build complete: $dest"

    # -- Step: Import ---------------------------------------------------------

    if ($ImportAfterBuild) {
        $step++
        Write-PipelineStep -Index $step -Total $totalSteps -Label 'Dev Import'

        $LASTEXITCODE = 0
        & (Join-Path -Path $privateTools -ChildPath 'DevImport.ps1') -Quiet

        if ($LASTEXITCODE -ne 0) {
            Stop-Pipeline -Reason 'Module import failed after build.'
        }

        Write-PipelineResult -Success $true -Message 'Module imported successfully.'
    }

    # -- Step: Manifest validation --------------------------------------------

    $step++
    Write-PipelineStep -Index $step -Total $totalSteps -Label 'Manifest validation'

    $meta = Import-PowerShellDataFile -Path $manifestPath

    $requiredFields = [ordered]@{
        ModuleVersion    = $meta.ModuleVersion
        Author           = $meta.Author
        Description      = $meta.Description
        RootModule       = $meta.RootModule
        FormatsToProcess = if ($meta.FormatsToProcess.Count -gt 0) { 'present' } else { $null }
    }

    $manifestErrors = $requiredFields.GetEnumerator() |
        Where-Object -FilterScript { [string]::IsNullOrWhiteSpace($_.Value) } |
        ForEach-Object { "Missing required field in manifest: $($_.Key)" }

    if ($manifestErrors) {
        foreach ($err in $manifestErrors) {
            Write-Host "    - $err" -ForegroundColor Yellow
        }
        Stop-Pipeline -Reason 'Manifest validation failed.'
    }

    Write-PipelineResult -Success $true -Message "Manifest valid (v$($meta.ModuleVersion), $($meta.FunctionsToExport.Count) exports)."

    # -- Step: Publish --------------------------------------------------------

    if ($Publish) {
        $step++
        Write-PipelineStep -Index $step -Total $totalSteps -Label 'Publish (PowerShell Gallery)'

        $apiKey = $env:PSGALLERY_API_KEY

        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            Stop-Pipeline -Reason 'PSGALLERY_API_KEY environment variable is not set.'
        }

        Publish-Module -Path $dest -NuGetApiKey $apiKey -ErrorAction Stop

        Write-PipelineResult -Success $true -Message "Published RDPControl v$version to PowerShell Gallery."
    }
}

# -- Step: DevImport ----------------------------------------------------------

if ($DevImport) {
    $step++
    Write-PipelineStep -Index $step -Total $totalSteps -Label 'Dev Import (source)'

    $LASTEXITCODE = 0
    & (Join-Path -Path $privateTools -ChildPath 'DevImport.ps1') -Quiet

    if ($LASTEXITCODE -ne 0) {
        Stop-Pipeline -Reason 'Module import failed.'
    }

    Write-PipelineResult -Success $true -Message 'Module imported from source successfully.'
}

# -- Footer -------------------------------------------------------------------

Write-Host ''
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host "  Pipeline complete  RDPControl v$version" -ForegroundColor Green
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''
