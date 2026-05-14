<#
.SYNOPSIS
Builds the RDPControl module into a versioned output artifact.

.DESCRIPTION
Copies source files into output/RDPControl/<version>/ and writes a
SHA-256 integrity manifest (hashes.json) alongside the module files.

Optionally runs lint and tests before building, and publishes to the
PowerShell Gallery.

Exit codes:
    0 - build succeeded
    1 - lint, test, or build step failed

.PARAMETER SkipLint
Skips PSScriptAnalyzer before building.

.PARAMETER SkipTests
Skips Pester tests before building.

.PARAMETER NoCoverage
Skips code coverage when tests run.

.PARAMETER Publish
Publishes to the PowerShell Gallery after building.
Requires the PSGALLERY_API_KEY environment variable.

.EXAMPLE
PS C:\> .\tools\private\Build.ps1

.EXAMPLE
PS C:\> .\tools\private\Build.ps1 -SkipTests

.EXAMPLE
PS C:\> .\tools\private\Build.ps1 -Publish
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param (
    [Parameter()]
    [switch]$SkipLint,

    [Parameter()]
    [switch]$SkipTests,

    [Parameter()]
    [switch]$NoCoverage,

    [Parameter()]
    [switch]$Publish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root         = (Get-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).FullName
$privateTools = $PSScriptRoot
$manifestPath = Join-Path -Path $root -ChildPath 'RDPControl.psd1'
$outputPath   = Join-Path -Path $root -ChildPath 'output'

$moduleData = Import-PowerShellDataFile -Path $manifestPath
$version    = $moduleData.ModuleVersion

Write-Host ''
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host "  Build  RDPControl v$version" -ForegroundColor Cyan
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''

if (-not $SkipLint) {
    Write-Host '  [1] Lint...' -ForegroundColor Gray
    & (Join-Path -Path $privateTools -ChildPath 'Lint.ps1') -Strict

    if ($LASTEXITCODE -ne 0) {
        Write-Host '  [ABORTED] Lint failed.' -ForegroundColor Red
        exit 1
    }
}

if (-not $SkipTests) {
    Write-Host '  [2] Tests...' -ForegroundColor Gray
    $testArgs = @{}

    if (-not $NoCoverage) {
        $testArgs.Coverage = $true
    }

    & (Join-Path -Path $privateTools -ChildPath 'Tests.ps1') @testArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host '  [ABORTED] Tests failed.' -ForegroundColor Red
        exit 1
    }
}

Write-Host '  [3] Building artifact...' -ForegroundColor Gray

$dest = Join-Path -Path $outputPath -ChildPath "RDPControl\$version"

if (Test-Path -LiteralPath $dest) {
    Remove-Item -Path $dest -Recurse -Force
}

New-Item -ItemType Directory -Path $dest | Out-Null

foreach ($dir in @('src', 'lib')) {
    $src = Join-Path -Path $root -ChildPath $dir
    if (Test-Path -LiteralPath $src -PathType Container) {
        Copy-Item -Path $src -Destination (Join-Path -Path $dest -ChildPath $dir) -Recurse
    }
}

foreach ($file in @('RDPControl.psd1', 'RDPControl.psm1', 'LICENSE', 'CHANGELOG.md', 'README.md')) {
    $src = Join-Path -Path $root -ChildPath $file
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        Copy-Item -Path $src -Destination $dest
    }
}

# Write SHA-256 integrity manifest
$hashes = Get-ChildItem -Path $dest -Recurse -File | ForEach-Object {
    $rel  = $_.FullName.Substring($dest.Length + 1) -replace '\\', '/'
    $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
    [ordered]@{ file = $rel; sha256 = $hash }
}

[ordered]@{
    module  = 'RDPControl'
    version = $version
    builtAt = (Get-Date -Format 'o')
    files   = $hashes
} | ConvertTo-Json -Depth 5 |
    Set-Content -Path (Join-Path -Path $dest -ChildPath 'hashes.json') -Encoding UTF8

Write-Host ''
Write-Host "  Output : $dest" -ForegroundColor Green
Write-Host "  Files  : $($hashes.Count) (hashes.json written)" -ForegroundColor Gray

if ($Publish) {
    Write-Host ''
    Write-Host '  [4] Publishing...' -ForegroundColor Gray

    $apiKey = $env:PSGALLERY_API_KEY

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Host '  [ABORTED] PSGALLERY_API_KEY environment variable is not set.' -ForegroundColor Red
        exit 1
    }

    Publish-Module -Path $dest -NuGetApiKey $apiKey -ErrorAction Stop
    Write-Host "  Published RDPControl v$version to PowerShell Gallery." -ForegroundColor Green
}

Write-Host ''
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host "  Build complete  RDPControl v$version" -ForegroundColor Green
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''
