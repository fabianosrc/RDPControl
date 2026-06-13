<#
.SYNOPSIS
Maps an exception to an appropriate ErrorCategory based on its type.

.DESCRIPTION
Determines the correct System.Management.Automation.ErrorCategory for
an exception based on its .NET type, rather than parsing the exception
message.

Message-based classification is unreliable because exception messages
vary by Windows locale (for example, "Access is denied" in en-US versus
"Acesso negado" in pt-BR), by .NET version, and by the underlying API
that raised the error. Classifying by exception type avoids this
fragility entirely.

.PARAMETER Exception
The exception to classify.

.EXAMPLE
PS C:\> Get-RdpErrorCategory -Exception $_.Exception

.INPUTS
None

.OUTPUTS
System.Management.Automation.ErrorCategory
#>
function Get-RdpErrorCategory {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorCategory])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Exception]$Exception
    )

    switch ($Exception) {
        { $_ -is [System.UnauthorizedAccessException] } {
            return [System.Management.Automation.ErrorCategory]::PermissionDenied
        }
        { $_ -is [System.Security.SecurityException] } {
            return [System.Management.Automation.ErrorCategory]::PermissionDenied
        }
        { $_ -is [System.Security.Principal.IdentityNotMappedException] } {
            return [System.Management.Automation.ErrorCategory]::ObjectNotFound
        }
        { $_ -is [System.Management.Automation.ItemNotFoundException] } {
            return [System.Management.Automation.ErrorCategory]::ObjectNotFound
        }
        default {
            return [System.Management.Automation.ErrorCategory]::WriteError
        }
    }
}
