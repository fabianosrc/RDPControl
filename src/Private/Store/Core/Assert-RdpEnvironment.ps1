<#
.SYNOPSIS
Asserts that the RDPControl environment has been initialized.

.DESCRIPTION
Throws a terminating error if the environment file is not found.
Intended as a guard clause at the start of every public cmdlet.

.EXAMPLE
PS C:\> Assert-RdpEnvironment

.OUTPUTS
None
#>
function Assert-RdpEnvironment {
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    $envFile = Join-Path -Path $env:ProgramData -ChildPath 'RDPControl\environment.json'

    if (Test-Path -LiteralPath $envFile -PathType Leaf) {
        return
    }

    $err = [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new(
            'RDPControl environment not found. Run Initialize-RdpEnvironment before using this cmdlet.'
        ),
        'EnvironmentNotInitialized',
        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
        $envFile
    )

    $PSCmdlet.ThrowTerminatingError($err)
}
