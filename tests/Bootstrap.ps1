#Requires -Version 5.1

$Script:RepositoryRoot = (
    Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
).Path

$Script:ModuleManifest = Join-Path $Script:RepositoryRoot 'RDPControl.psd1'

if (-not (Test-Path -LiteralPath $Script:ModuleManifest -PathType Leaf)) {
    throw "Module manifest not found: $Script:ModuleManifest"
}

$moduleName = [System.IO.Path]::GetFileNameWithoutExtension(
    $Script:ModuleManifest
)

$Script:LoadedModule = Get-Module -Name $moduleName

if (-not $Script:LoadedModule) {
    $moduleParams = @{
        Name     = $Script:ModuleManifest
        Force    = $true
        PassThru = $true
    }

    $Script:LoadedModule = Import-Module @moduleParams
}

[PSCustomObject]@{
    RepositoryRoot = $Script:RepositoryRoot
    ModuleManifest = $Script:ModuleManifest
    Module         = $Script:LoadedModule
}
