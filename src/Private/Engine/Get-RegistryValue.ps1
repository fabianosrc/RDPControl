<#
.SYNOPSIS
Retrieves a registry value from a specified path.

.DESCRIPTION
Reads a single registry value from the Windows registry using a robust,
enterprise-grade approach suitable for automation modules and pipelines.

- Returns $null if key/value does not exist (unless -Strict is specified)
- Uses structured ErrorRecord for terminating errors
- Avoids silent failures from registry provider ambiguity
- Validates property existence explicitly
- Designed for composability in large PowerShell modules

.PARAMETER Path
Registry key path (e.g. HKLM:\SOFTWARE\...).

.PARAMETER Name
Registry value name to retrieve.

.PARAMETER Strict
When set, throws terminating errors if key or value is not found.

.EXAMPLE
PS C:\> Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'PortNumber'

.EXAMPLE
PS C:\> Get-RegistryValue -Path 'HKLM:\SOFTWARE\Example' -Name 'Setting' -Strict

.INPUTS
None

.OUTPUTS
System.Object
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

        [switch]$Strict
    )

    process {

        # -----------------------------
        # 1. Validate registry key
        # -----------------------------
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Container)) {

                if ($Strict) {
                    $PSCmdlet.ThrowTerminatingError(
                        [System.Management.Automation.ErrorRecord]::new(
                            [System.IO.DirectoryNotFoundException]::new(
                                "Registry key not found: $Path"
                            ),
                            'RegistryKeyNotFound',
                            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                            $Path
                        )
                    )
                }

                return $null
            }
        } catch {
            if ($Strict) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        $_.Exception,
                        'RegistryKeyValidationFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $Path
                    )
                )
            }

            return $null
        }

        # -----------------------------
        # 2. Read registry item safely
        # -----------------------------
        $item = $null

        try {
            $item = Get-ItemProperty -LiteralPath $Path
        } catch {
            if ($Strict) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        $_.Exception,
                        'RegistryReadFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError,
                        $Path
                    )
                )
            }

            return $null
        }

        # -----------------------------
        # 3. Validate property existence
        # -----------------------------
        $hasProperty = $item.PSObject.Properties.Name -contains $Name

        if (-not $hasProperty) {
            if ($Strict) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Collections.Generic.KeyNotFoundException]::new(
                            "Registry value '$Name' not found under '$Path'"
                        ),
                        'RegistryValueNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $Name
                    )
                )
            }

            return $null
        }

        # -----------------------------
        # 4. Return value
        # -----------------------------
        return $item.$Name
    }
}
