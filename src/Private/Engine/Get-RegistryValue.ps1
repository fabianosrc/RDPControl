<#
.SYNOPSIS
Reads a value from the Windows Registry.

.DESCRIPTION
Retrieves a single registry value by path and name. Returns $null if the key
or value does not exist, unless -Strict is specified, in which case it throws.

.PARAMETER Path
Full registry path (e.g. 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server').

.PARAMETER Name
Name of the registry value to read.

.PARAMETER Strict
When specified, throws an error if the key or value does not exist.

.EXAMPLE
PS C:\> $port = Get-RegistryValue -Path 'HKLM:\SYSTEM\...\RDP-Tcp' -Name 'PortNumber'

.OUTPUTS
System.Object - the registry value, or $null if not found (unless -Strict is used).
    #>
function Get-RegistryValue {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [switch]$Strict
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        if ($Strict) {
            throw "Registry key not found: [$Path]"
        }

        return $null
    }

    try {
        $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    } catch {
        if ($Strict) {
            throw
        }

        return $null
    }

    if (-not ($item.PSObject.Properties.Name -contains $Name)) {
        if ($Strict) {
            throw "Registry value not found: [$Name] under [$Path]"
        }

        return $null
    }

    return $item.$Name
}
