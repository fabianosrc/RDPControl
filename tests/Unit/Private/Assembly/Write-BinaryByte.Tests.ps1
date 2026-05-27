Describe 'Write-BinaryByte' {
    BeforeAll {
        . "$PSScriptRoot/../../../../src/Private/Assembly/Write-BinaryByte.ps1"

        $Script:TestDir = Join-Path -Path $TestDrive -ChildPath 'WriteBinaryByte'

        New-Item -Path $Script:TestDir -ItemType Directory -Force | Out-Null

        function New-TestBinaryFile {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions',
                '',
                Justification = 'Internal test helper.'
            )]
            param (
                [Parameter(Mandatory)]
                [string]$Name,

                [Parameter(Mandatory)]
                [byte[]]$Bytes
            )

            $path = Join-Path -Path $Script:TestDir -ChildPath $Name

            [System.IO.File]::WriteAllBytes($path, $Bytes)

            return $path
        }

        function Read-TestBinaryFile {
            param(
                [Parameter(Mandatory)]
                [string]$Path
            )

            return [System.IO.File]::ReadAllBytes($Path)
        }
    }

    Context 'Successful writes' {
        It 'Writes bytes at the specified offset' {
            $filePath = New-TestBinaryFile -Name 'write_basic.bin' -Bytes ([byte[]](0x00, 0x00, 0x00, 0x00, 0x00))

            Write-BinaryByte -Path $filePath -Offset 2 -Bytes ([byte[]](0xAA, 0xBB)) | Out-Null

            [byte[]]$result = Read-TestBinaryFile -Path $filePath

            $result | Should -Be ([byte[]](0x00, 0x00, 0xAA, 0xBB, 0x00))
        }

        It 'Writes bytes at offset zero' {
            $filePath = New-TestBinaryFile -Name 'write_offset0.bin' -Bytes ([byte[]](0xFF, 0xFF, 0xFF))

            Write-BinaryByte -Path $filePath -Offset 0 -Bytes ([byte[]](0x01, 0x02)) | Out-Null

            [byte[]]$result = Read-TestBinaryFile -Path $filePath

            $result | Should -Be ([byte[]](0x01, 0x02, 0xFF))
        }

        It 'Writes bytes at the last valid offset' {
            $filePath = New-TestBinaryFile -Name 'write_last_offset.bin' -Bytes ([byte[]](0x00, 0x00, 0x00, 0x00))

            Write-BinaryByte -Path $filePath -Offset 3 -Bytes ([byte[]](0xDD)) | Out-Null

            [byte[]]$result = Read-TestBinaryFile -Path $filePath

            $result | Should -Be ([byte[]](0x00, 0x00, 0x00, 0xDD))
        }

        It 'Does not change the file size' {
            $filePath = New-TestBinaryFile -Name 'write_size.bin' -Bytes ([byte[]]::new(100))

            Write-BinaryByte -Path $filePath -Offset 50 -Bytes ([byte[]](0xAA, 0xBB, 0xCC)) | Out-Null

            $fileInfo = Get-Item -Path $filePath

            $fileInfo.Length | Should -Be 100
        }

        It 'Preserves bytes outside the write region' {
            $filePath = New-TestBinaryFile -Name 'write_preserve.bin' -Bytes ([byte[]](0x11, 0x22, 0x33, 0x44, 0x55))

            Write-BinaryByte -Path $filePath -Offset 2 -Bytes ([byte[]](0xFF)) | Out-Null

            [byte[]]$result = Read-TestBinaryFile -Path $filePath

            $result | Should -Be ([byte[]](0x11, 0x22, 0xFF, 0x44, 0x55))
        }

        It 'Produces the same result when writing identical bytes twice' {
            $filePath = New-TestBinaryFile -Name 'write_idempotent.bin' -Bytes ([byte[]](0x00, 0x00, 0x00, 0x00))

            [byte[]]$payload = 0xAA, 0xBB

            Write-BinaryByte -Path $filePath -Offset 1 -Bytes $payload | Out-Null
            Write-BinaryByte -Path $filePath -Offset 1 -Bytes $payload | Out-Null

            [byte[]]$result = Read-TestBinaryFile -Path $filePath

            $result | Should -Be ([byte[]](0x00, 0xAA, 0xBB, 0x00))
        }

        It 'Does not lock the file after writing' {
            $filePath = New-TestBinaryFile -Name 'write_unlock.bin' -Bytes ([byte[]](0x00, 0x00))

            Write-BinaryByte -Path $filePath -Offset 0 -Bytes ([byte[]](0xAA)) | Out-Null

            { Remove-Item -Path $filePath -Force } | Should -Not -Throw
        }
    }

    Context 'Output object contract' {
        It 'Returns a PSCustomObject' {
            $filePath = New-TestBinaryFile -Name 'write_object.bin' -Bytes ([byte[]](0x00))

            $result = Write-BinaryByte -Path $filePath -Offset 0 -Bytes ([byte[]](0xAA))

            $result | Should -BeOfType [pscustomobject]
        }

        It 'Returns the expected properties' {
            $filePath = New-TestBinaryFile -Name 'write_properties.bin' -Bytes ([byte[]](0x00))

            $result = Write-BinaryByte -Path $filePath -Offset 0 -Bytes ([byte[]](0xAA))

            $result.PSObject.Properties.Name | Should -Contain 'Path'
            $result.PSObject.Properties.Name | Should -Contain 'Offset'
            $result.PSObject.Properties.Name | Should -Contain 'Length'
            $result.PSObject.Properties.Name | Should -Contain 'Success'
        }

        It 'Returns the correct metadata values' {
            $filePath = New-TestBinaryFile -Name 'write_metadata.bin' -Bytes ([byte[]]::new(50))

            [byte[]]$payload = 0x01, 0x02, 0x03

            $result = Write-BinaryByte -Path $filePath -Offset 10 -Bytes $payload

            $result.Path    | Should -Be $filePath
            $result.Offset  | Should -Be 10
            $result.Length  | Should -Be 3
            $result.Success | Should -BeTrue
        }

        It 'Returns strongly typed metadata values' {
            $filePath = New-TestBinaryFile -Name 'write_types.bin' -Bytes ([byte[]](0x00))

            $result = Write-BinaryByte -Path $filePath -Offset 0 -Bytes ([byte[]](0xAA))

            $result.Path    | Should -BeOfType [string]
            $result.Offset  | Should -BeOfType [int64]
            $result.Length  | Should -BeOfType [int32]
            $result.Success | Should -BeOfType [bool]
        }

        It 'Has PSTypeName RDPControl.BinaryWriteResult' {
            $filePath = New-TestBinaryFile -Name 'write_typename.bin' -Bytes ([byte[]](0x00))

            $result = Write-BinaryByte -Path $filePath -Offset 0 -Bytes ([byte[]](0xAA))

            $result.PSTypeNames | Should -Contain 'RDPControl.BinaryWriteResult'
        }
    }

    Context 'Invalid paths' {
        It 'Throws when the specified file does not exist' {
            { Write-BinaryByte -Path 'C:\nonexistent\fake.dll' -Offset 0 -Bytes ([byte[]](0xAA)) } | Should -Throw
        }

        It 'Throws when Path is null or empty' {
            { Write-BinaryByte -Path '' -Offset 0 -Bytes ([byte[]](0xAA)) } | Should -Throw
        }
    }

    Context 'Invalid offsets and bounds' {
        It 'Throws when Offset is negative' {
            $filePath = New-TestBinaryFile -Name 'negative_offset.bin' -Bytes ([byte[]](0x00))

            { Write-BinaryByte -Path $filePath -Offset -1 -Bytes ([byte[]](0xAA)) } | Should -Throw
        }

        It 'Throws when Offset equals file size' {
            $filePath = New-TestBinaryFile -Name 'offset_equals_size.bin' -Bytes ([byte[]](0x00, 0x00))

            { Write-BinaryByte -Path $filePath -Offset 2 -Bytes ([byte[]](0xAA)) } | Should -Throw
        }

        It 'Throws when Offset exceeds file size' {
            $filePath = New-TestBinaryFile -Name 'offset_beyond_size.bin' -Bytes ([byte[]](0x00))

            { Write-BinaryByte -Path $filePath -Offset 100 -Bytes ([byte[]](0xAA)) } | Should -Throw
        }

        It 'Throws when write exceeds file bounds' {
            $filePath = New-TestBinaryFile -Name 'write_overflow.bin' -Bytes ([byte[]](0x00, 0x00, 0x00))

            { Write-BinaryByte -Path $filePath -Offset 2 -Bytes ([byte[]](0xAA, 0xBB, 0xCC)) } | Should -Throw
        }
    }

    Context 'Invalid byte input' {
        It 'Throws when Bytes is empty' {
            $filePath = New-TestBinaryFile -Name 'empty_bytes.bin' -Bytes ([byte[]](0x00))

            { Write-BinaryByte -Path $filePath -Offset 0 -Bytes ([byte[]]@()) } | Should -Throw
        }

        It 'Throws when Bytes is null' {
            $filePath = New-TestBinaryFile -Name 'null_bytes.bin' -Bytes ([byte[]](0x00))

            { Write-BinaryByte -Path $filePath -Offset 0 -Bytes $null } | Should -Throw
        }
    }

    Context 'Read-only file handling' {
        It 'Throws when attempting to write to a read-only file' {
            $filePath = New-TestBinaryFile -Name 'readonly.bin' -Bytes ([byte[]](0x00, 0x00))

            $file = Get-Item -Path $filePath
            $file.IsReadOnly = $true

            try {
                { Write-BinaryByte -Path $filePath -Offset 0 -Bytes ([byte[]](0xAA)) } | Should -Throw

            } finally {
                $file.IsReadOnly = $false
            }
        }
    }
}
