<#
.SYNOPSIS
Configures Remote Desktop access state using CIM with registry fallback.

.DESCRIPTION
Attempts to configure Remote Desktop access using the Win32_TerminalServiceSetting
CIM class, which properly synchronizes the Windows Settings UI toggle, firewall
rules, and the operational state of the Remote Desktop service in a single call.

CIM transport selection follows this order:
    1. WSMan  - preferred; works on Windows 11 and remote targets
    2. DCOM   - fallback; required on Windows 10 local sessions

If both CIM transports fail, automatically falls back to registry-based
configuration. The fallback also manages the Windows Settings UI toggle:

    - Enabling  : removes the policy key so the Settings UI returns to user control
    - Disabling : writes to the policy key so the Settings UI reflects the locked state

Writing any value to the policy key - including 0 - causes Windows to display
"some settings are managed by your organization" and lock the toggle. The key
must be removed, not zeroed, to release UI control back to the user.

This hybrid approach guarantees compatibility across:
    - Windows 10
    - Windows 11
    - Windows Server
    - Hyper-V virtual machines
    - Hardened environments
    - Restricted WMI/DCOM environments

.PARAMETER AllowConnections
When $true, enables Remote Desktop access.
When $false, disables Remote Desktop access.

.PARAMETER ComputerName
Target computer name. Defaults to the local machine.
Reserved for future remote activation support.

.OUTPUTS
PSCustomObject

Contains:
    Success  [bool]   - whether the operation succeeded
    Method   [string] - CIM, or RegistryFallback
#>
function Set-RdpAccessState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'ShouldProcess is handled by the public cmdlet caller.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [bool]$AllowConnections,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName = $env:COMPUTERNAME
    )

    process {
        $allowValue = [int]$AllowConnections
        $session    = $null

        # -- CIM path ---------------------------------------------------------
        # SetAllowTSConnections synchronizes the Windows Settings UI toggle,
        # firewall rules, and the RDP operational state in a single call.
        #
        # Transport selection:
        #   WSMan : preferred - works on Windows 11 and remote targets.
        #           ComputerName='localhost' triggers DCOM on Win11, causing
        #           access denied errors; WSMan avoids this entirely.
        #   DCOM  : fallback - required on Windows 10 local sessions where
        #           WSMan may not be available or configured.
        # ---------------------------------------------------------------------

        try {
            $namespace = 'root/cimv2/TerminalServices'

            try {
                $sessionOption = New-CimSessionOption -Protocol Wsman
                $session       = New-CimSession -ComputerName $ComputerName -SessionOption $sessionOption

                Write-Verbose -Message "CIM session established via WSMan to '$ComputerName'."
            } catch {
                Write-Verbose -Message "WSMan transport unavailable, retrying via DCOM. $($_.Exception.Message)"

                $sessionOption = New-CimSessionOption -Protocol Dcom
                $session       = New-CimSession -ComputerName $ComputerName -SessionOption $sessionOption

                Write-Verbose -Message "CIM session established via DCOM to '$ComputerName'."
            }

            $rdp = Get-CimInstance -CimSession $session -Namespace $namespace -ClassName 'Win32_TerminalServiceSetting'

            if ($null -eq $rdp) {
                throw 'Win32_TerminalServiceSetting class not found.'
            }

            $result = $rdp | Invoke-CimMethod -MethodName 'SetAllowTSConnections' -Arguments @{
                AllowTSConnections      = $allowValue
                ModifyFirewallException = 1
            }

            if ($result.ReturnValue -ne 0) {
                throw "SetAllowTSConnections returned error code: $($result.ReturnValue)"
            }

            Write-Verbose -Message "Remote Desktop access configured via CIM (AllowConnections=$AllowConnections)."

            return [PSCustomObject]@{
                Success = $true
                Method  = 'CIM'
            }
        } catch {
            Write-Verbose -Message "CIM configuration unavailable, falling back to registry. $($_.Exception.Message)"
        } finally {
            if ($null -ne $session) {
                $session.Dispose()
            }
        }

        # -- Registry fallback ------------------------------------------------
        # Writes to the operational key that controls RDP connectivity.
        # Also manages the policy key read by the Windows Settings UI toggle:
        #
        #   Enabling  -> Remove-ItemProperty on the policy key. Any value under
        #                the policy path causes Windows to show "some settings
        #                are managed by your organization" and lock the toggle.
        #                Removing the key releases UI control back to the user.
        #
        #   Disabling -> Write 1 to the policy key so the Settings UI reflects
        #                the locked/disabled state correctly.
        #
        # UI sync is non-fatal - a failure logs a verbose message but does not
        # abort the configuration.
        # ---------------------------------------------------------------------

        try {
            $denyValue   = [int](-not $AllowConnections)
            $termSrvPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
            $policyPath  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'

            Set-RegistryValue -Path $termSrvPath -Name 'fDenyTSConnections' -Value $denyValue -Type 'DWord'

            try {
                if ($AllowConnections) {
                    Remove-ItemProperty -Path $policyPath -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue
                } else {
                    Set-RegistryValue -Path $policyPath -Name 'fDenyTSConnections' -Value 1 -Type 'DWord'
                }

                Write-Verbose -Message 'Windows Settings UI toggle synchronized via policy key.'
            } catch {
                Write-Verbose -Message "Could not synchronize Windows Settings UI toggle. This is non-fatal. $($_.Exception.Message)"
            }

            if ($AllowConnections) {
                Set-FirewallRule -Port (Get-RdpPort).Port
            } else {
                Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
            }

            Write-Verbose -Message "Remote Desktop access configured via registry fallback (AllowConnections=$AllowConnections)."

            return [PSCustomObject]@{
                Success = $true
                Method  = 'RegistryFallback'
            }
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'RdpConfigurationFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    'RemoteDesktop'
                )
            )
        }
    }
}
