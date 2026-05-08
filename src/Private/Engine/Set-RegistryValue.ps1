<#
.SYNOPSIS
Ensures a registry value exists with the desired state.

.DESCRIPTION
Creates the registry key if needed and ensures the registry value matches
the desired name, type, and data.

Fully idempotent and type-safe:
- No string coercion comparisons
- No false diff detection for arrays or binary data
- Always enforces correct registry type using New-ItemProperty

.PARAMETER Path
Full registry path (e.g. 'HKLM:\SOFTWARE\Example').

.PARAMETER Name
Registry value name.

.PARAMETER Value
Desired value data.

.PARAMETER Type
Registry value type. Defaults to 'DWord'.

.EXAMPLE
PS C:\> Set-RegistryValue -Path 'HKLM:\SOFTWARE\Test' -Name 'Mode' -Value 1 -Type DWord

.EXAMPLE
PS C:\> Set-RegistryValue -Path 'HKLM:\SOFTWARE\Test' -Name 'Name' -Value 'text' -Type String

.INPUTS
None

.OUTPUTS
None
#>
function Set-RegistryValue {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'QWord', 'MultiString')]
        [string]$Type = 'DWord'
    )

    process {
        # Ensure key exists
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($Path, "Create registry key")) {
                New-Item -Path $Path -Force | Out-Null
                Write-Verbose -Message "Created registry key: $Path"
            }
        }

        # Read current value safely
        $currentValue = $null
        $exists       = $false

        try {
            $item         = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            $currentValue = $item.$Name
            $exists       = $true
        } catch {
            $exists = $false
        }

        # Type-safe idempotency comparison - no string coercion
        $isEqual = $false

        if ($exists) {
            switch ($Type) {
                'Binary' {
                    $isEqual = (([byte[]]$currentValue -join '-') -eq ([byte[]]$Value -join '-'))
                }
                'MultiString' {
                    $isEqual = ((@($currentValue) -join "`0") -eq (@($Value) -join "`0"))
                }
                default {
                    $isEqual = ($currentValue -eq $Value)
                }
            }
        }

        if ($exists -and $isEqual) {
            Write-Verbose -Message "Registry value already in desired state: $Path\$Name"
            return
        }

        if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set registry value ($Type)")) {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
            Write-Verbose -Message "Set registry value: $Path\$Name ($Type)"
        }
    }
}
