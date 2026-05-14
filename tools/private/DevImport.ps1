<#
.SYNOPSIS
Imports the RDPControl module in development mode.

.DESCRIPTION
Forces a clean re-import of RDPControl from the local source tree.
Removes any previously loaded instance, validates the manifest, and
imports the module with optional verbose output and lint check.

Exit codes:
    0 - module imported successfully
    1 - import failed

.PARAMETER Quiet
Suppresses verbose output during import.

.PARAMETER SkipLint
Skips the PSScriptAnalyzer check after import.

.EXAMPLE
PS C:\> .\tools\private\DevImport.ps1

.EXAMPLE
PS C:\> .\tools\private\DevImport.ps1 -Quiet

.EXAMPLE
PS C:\> .\tools\private\DevImport.ps1 -Quiet -SkipLint
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param (
    [Parameter()]
    [switch]$Quiet,

    [Parameter()]
    [switch]$SkipLint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleName   = 'RDPControl'
$moduleRoot   = (Get-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).FullName
$manifestPath = Join-Path -Path $moduleRoot -ChildPath "$moduleName.psd1"
$privateTools = $PSScriptRoot

Write-Host ''
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host '  RDPControl  Dev Import' -ForegroundColor Cyan
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Host "  [ERROR] Manifest not found: $manifestPath" -ForegroundColor Red
    exit 1
}

$loaded = Get-Module -Name $moduleName -ErrorAction SilentlyContinue

if ($loaded) {
    Write-Host "  Removing loaded module: v$($loaded.Version)" -ForegroundColor Yellow
    Remove-Module -Name $moduleName -Force
}

Write-Host "  Importing: $manifestPath" -ForegroundColor Gray
Write-Host ''

try {
    if ($Quiet) {
        Import-Module -Name $manifestPath -Force
    } else {
        Import-Module -Name $manifestPath -Force -Verbose
    }
} catch {
    Write-Host ''
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    exit 1
}

$module = Get-Module -Name $moduleName -ErrorAction SilentlyContinue

if (-not $module) {
    Write-Host "  [ERROR] Module was not loaded after import." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host "  Module   : $($module.Name) v$($module.Version)" -ForegroundColor Green
Write-Host "  Commands : $($module.ExportedCommands.Count) exported" -ForegroundColor Green
Write-Host "  Path     : $($module.Path)" -ForegroundColor Gray
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''

$module.ExportedCommands.Keys | Sort-Object | ForEach-Object {
    Write-Host "    $_" -ForegroundColor DarkCyan
}

Write-Host ''

if (-not $SkipLint) {
    $analyzer = Get-Module -Name PSScriptAnalyzer -ListAvailable -ErrorAction SilentlyContinue

    if (-not $analyzer) {
        Write-Host '  PSScriptAnalyzer not installed - skipping lint.' -ForegroundColor DarkGray
        Write-Host '  Install with: Install-Module PSScriptAnalyzer -Scope CurrentUser' -ForegroundColor DarkGray
        Write-Host ''
        exit 0
    }

    Write-Host '  Running PSScriptAnalyzer...' -ForegroundColor Gray
    Write-Host ''

    & (Join-Path -Path $privateTools -ChildPath 'Lint.ps1')
}
