#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Bootstrap

$Script:ModuleRoot  = $PSScriptRoot
$Script:SourceRoot  = Join-Path -Path $Script:ModuleRoot -ChildPath 'src'
$Script:LibRoot     = Join-Path -Path $Script:ModuleRoot -ChildPath 'lib'

$Script:Runtime = if ($PSVersionTable.PSEdition -eq 'Core') {
    'netstandard2.0'
} else {
    'net46'
}

$Script:Architecture = if ([System.Environment]::Is64BitProcess) {
    'x64'
} else {
    'x86'
}

#endregion

#region SQLite - Native interop path

$Script:NativeInteropDirectory = Join-Path -Path $Script:LibRoot -ChildPath (
    '{0}\{1}' -f $Script:Runtime, $Script:Architecture
)

if (Test-Path -LiteralPath $Script:NativeInteropDirectory -PathType Container) {
    $pathEntries = $env:PATH -split ';'

    if ($pathEntries -notcontains $Script:NativeInteropDirectory) {
        $env:PATH = '{0};{1}' -f $Script:NativeInteropDirectory, $env:PATH
    }
} else {
    Write-Warning -Message "[RDPControl] SQLite native interop directory not found: $Script:NativeInteropDirectory"
}

#endregion

#region SQLite - Managed assembly

$Script:ManagedAssemblyPath = Join-Path -Path $Script:LibRoot -ChildPath (
    '{0}\System.Data.SQLite.dll' -f $Script:Runtime
)

if (-not (Test-Path -LiteralPath $Script:ManagedAssemblyPath -PathType Leaf)) {
    Write-Warning -Message "[RDPControl] SQLite managed assembly not found: $Script:ManagedAssemblyPath"
} else {
    $alreadyLoaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object -FilterScript { $_.Location -eq $Script:ManagedAssemblyPath }

    if (-not $alreadyLoaded) {
        try {
            [void][System.Reflection.Assembly]::LoadFrom($Script:ManagedAssemblyPath)
        } catch {
            Write-Warning -Message "[RDPControl] Failed to load SQLite assembly: $($_.Exception.Message)"
        }
    }

    try {
        [void][System.Data.SQLite.SQLiteConnection]
    } catch {
        Write-Warning -Message "[RDPControl] SQLite assembly validation failed: $($_.Exception.Message)"
    }
}

#endregion

#region Interop bootstrap

$Script:InteropPath = Join-Path -Path $Script:SourceRoot -ChildPath 'Private\Interop\RdpControlInterop.ps1'

if (Test-Path -LiteralPath $Script:InteropPath -PathType Leaf) {
    try {
        . $Script:InteropPath
    } catch {
        Write-Warning -Message "[RDPControl] Failed to load interop bootstrap: $($_.Exception.Message)"
    }
} else {
    Write-Warning -Message "[RDPControl] Interop bootstrap not found: $Script:InteropPath"
}

#endregion

#region Private functions

$Script:PrivateDomains = @(
    'Assembly'
    'Engine'
    'Store\Providers'
    'Store\Core'
    'Enforcement'
)

foreach ($domain in $Script:PrivateDomains) {
    $domainPath = Join-Path -Path $Script:SourceRoot -ChildPath "Private\$domain"

    if (-not (Test-Path -LiteralPath $domainPath -PathType Container)) {
        Write-Warning -Message "[RDPControl] Private domain directory not found: $domainPath"
        continue
    }

    $files = Get-ChildItem -Path $domainPath -Filter '*.ps1' -File -Recurse | Sort-Object -Property FullName

    foreach ($file in $files) {
        try {
            . $file.FullName

            $fn = Get-Command -Name $file.BaseName -CommandType Function -ErrorAction SilentlyContinue

            if (-not $fn) {
                Write-Warning -Message "[RDPControl] Expected function [$($file.BaseName)] not found after loading [$($file.Name)]."
            } else {
                Write-Verbose -Message "[RDPControl] Loaded private: $($file.BaseName)"
            }
        } catch {
            Write-Warning -Message "[RDPControl] Failed to load private script [$($file.Name)]: $($_.Exception.Message)"
        }
    }
}

#endregion

#region Public functions

$Script:PublicDomains = @(
    'Policy'
    'Snapshot'
    'Watchdog'
    'User'
    'Session'
)

$Script:ExportedFunctions = [System.Collections.Generic.List[string]]::new()

foreach ($domain in $Script:PublicDomains) {
    $domainPath = Join-Path -Path $Script:SourceRoot -ChildPath "Public\$domain"

    if (-not (Test-Path -LiteralPath $domainPath -PathType Container)) {
        Write-Warning -Message "[RDPControl] Public domain directory not found: $domainPath"
        continue
    }

    $files = Get-ChildItem -Path $domainPath -Filter '*.ps1' -File | Sort-Object -Property FullName

    foreach ($file in $files) {
        try {
            . $file.FullName

            $fn = Get-Command -Name $file.BaseName -CommandType Function -ErrorAction SilentlyContinue

            if (-not $fn) {
                Write-Warning -Message "[RDPControl] Expected function [$($file.BaseName)] not found after loading [$($file.Name)]."
            } else {
                [void]$Script:ExportedFunctions.Add($file.BaseName)
                Write-Verbose -Message "[RDPControl] Loaded public: $($file.BaseName)"
            }
        } catch {
            Write-Warning -Message "[RDPControl] Failed to load public script [$($file.Name)]: $($_.Exception.Message)"
        }
    }
}

#endregion

#region Export

Export-ModuleMember -Function $Script:ExportedFunctions

#endregion
