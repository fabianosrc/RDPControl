<#
.SYNOPSIS
Returns the current Remote Desktop session mode.

.DESCRIPTION
Returns the active session mode configuration for Remote Desktop,
including the current enforcement state and binary integrity hash.

.EXAMPLE
PS C:\> Get-RdpSessionMode

.INPUTS
None

.OUTPUTS
PSCustomObject

Contains:
- Mode      [string] - 'Concurrent' or 'Standard'
- Enforced  [bool]   - whether the session policy is enforced
- Hash      [string] - SHA256 of the current binary
- CheckedAt [string] - ISO 8601 UTC timestamp
#>
function Get-RdpSessionMode {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param ()

    begin {
        Assert-RdpEnvironment
    }

    process {
        $targetBinary = 'termsrv.dll'
        $targetPath   = Join-Path -Path $env:SystemRoot -ChildPath "System32\$targetBinary"

        $hash = $null

        try {
            if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
                $assembly = Read-PEFile -Path $targetPath
                $hash     = Get-BinaryHash -Bytes $assembly.Bytes
            }

            $isEnforced = Test-EnforcementState
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'GetRdpSessionModeFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $targetPath
                )
            )
        }

        [PSCustomObject]@{
            Mode      = if ($isEnforced) { 'Concurrent' } else { 'Standard' }
            Enforced  = $isEnforced
            Hash      = $hash
            CheckedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
