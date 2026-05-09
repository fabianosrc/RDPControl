<#
.SYNOPSIS
Asserts that the RDPControl environment has been initialized.

.DESCRIPTION
Verifies that the RDPControl environment file exists at the expected
ProgramData location.

Throws a terminating error if the environment has not been initialized,
instructing the caller to run Initialize-RdpControl first.

Intended to be used as a guard clause at the beginning of all public cmdlets.

.EXAMPLE
PS C:\> Assert-RdpEnvironment

.INPUTS
None

.OUTPUTS
None
#>
function Assert-RdpEnvironment {
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    $environmentPath = Join-Path -Path $env:ProgramData -ChildPath 'RDPControl\environment.json'

    if (Test-Path -LiteralPath $environmentPath -PathType Leaf) {
        Write-Verbose -Message "RDPControl environment found: $environmentPath"
        return
    }

    $err = [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new(
            'RDPControl environment is not initialized. ' +
            'Run Initialize-RdpControl before using this cmdlet.'
        ),
        'EnvironmentNotInitialized',
        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
        $environmentPath
    )

    $PSCmdlet.ThrowTerminatingError($err)
}
