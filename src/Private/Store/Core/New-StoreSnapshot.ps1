<#
.SYNOPSIS
Creates a new snapshot record in the RDPControl store.

.DESCRIPTION
Core Store operation that validates execution policy and delegates
persistence to the active provider implementation.

This cmdlet is part of the Store contract layer and is designed
for pipeline and automation usage.

.PARAMETER BinaryPath
Full path to the target binary.

.PARAMETER BinaryVersion
Version of the binary file.

.PARAMETER OsBuild
Windows OS build string.

.PARAMETER Sha256
SHA256 hash of the binary.

.PARAMETER BinaryBlob
Raw binary content.

.PARAMETER Enforced
Indicates whether this snapshot represents an enforced state.

.EXAMPLE
New-StoreSnapshot -BinaryPath "C:\example.dll" `
                  -BinaryVersion "10.0.19041.1" `
                  -OsBuild "19041" `
                  -Sha256 "ABC123..." `
                  -BinaryBlob $bytes `
                  -Enforced $false

.OUTPUTS
System.Int64
#>

function New-StoreSnapshot {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([long])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BinaryPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BinaryVersion,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OsBuild,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Sha256,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [byte[]]$BinaryBlob,

        [Parameter(Mandatory)]
        [bool]$Enforced
    )

    begin {
        Assert-RdpEnvironment
    }

    process {
        if (-not $PSCmdlet.ShouldProcess("Store Snapshot [$BinaryPath]", "Create snapshot record")) {
            return
        }

        $snapshotParams = @{
            BinaryPath    = $BinaryPath
            BinaryVersion = $BinaryVersion
            OsBuild       = $OsBuild
            Sha256        = $Sha256
            BinaryBlob    = $BinaryBlob
            Enforced      = $Enforced
        }

        return New-SQLiteSnapshot @snapshotParams
    }
}
