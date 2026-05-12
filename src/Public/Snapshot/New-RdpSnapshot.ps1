<#
.SYNOPSIS
Creates a manual snapshot of the current binary.

.DESCRIPTION
Reads the target binary, computes its SHA256 hash, and stores a snapshot
record in the database. Prevents duplicate snapshots using hash comparison.

.EXAMPLE
New-RdpSnapshot

.INPUTS
None

.OUTPUTS
PSCustomObject
Contains:
- Id
- BinaryVersion
- Sha256
- CreatedAt

.NOTES
Requires elevated privileges.
#>

function New-RdpSnapshot {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param ()

    begin {
        Assert-RdpEnvironment

        if (-not (Test-IsElevated)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new(
                        'New-RdpSnapshot requires elevated privileges. Run as Administrator.'
                    ),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }
    }

    process {
        $targetBinary = 'termsrv.dll'
        $targetPath = Join-Path $env:SystemRoot "System32\$targetBinary"

        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new(
                        'Target binary was not found.',
                        $targetPath
                    ),
                    'TargetBinaryNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $targetPath
                )
            )
        }

        if (-not $PSCmdlet.ShouldProcess($targetPath, 'Create snapshot')) {
            return
        }

        $assembly = Read-PEFile -Path $targetPath

        $hash = Get-BinaryHash -Bytes $assembly.Bytes

        $versionParams = @{ Path = $targetPath }

        $binVersion = Get-BinaryVersion @versionParams

        $osVersion = (Get-CimInstance -ClassName Win32_OperatingSystem).BuildNumber

        $existing = @(Get-StoreSnapshot -Sha256 $hash)

        if ($existing.Count -gt 0) {
            Write-Warning -Message "Snapshot already exists (ID: $($existing[0].Id))"
            return
        }

        $snapshotParams = @{
            BinaryPath     = $targetPath
            BinaryVersion  = $binVersion
            OsBuild        = $osVersion
            Sha256         = $hash
            BinaryBlob     = $assembly.Bytes
            Enforced       = $false
        }

        $id = New-StoreSnapshot @snapshotParams

        Write-Verbose -Message "Snapshot saved. ID: $id"

        [PSCustomObject]@{
            Id            = $id
            BinaryVersion = $binVersion
            Sha256        = $hash
            CreatedAt     = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
