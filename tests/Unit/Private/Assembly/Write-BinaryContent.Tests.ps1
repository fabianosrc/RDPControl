#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Assembly/Write-BinaryContent.ps1"
}

Describe 'Write-BinaryContent' {

    Context 'Input validation - Path' {

        It 'Throws BinaryFileNotFound when file does not exist' {
            $nonExistentPath = Join-Path -Path $TestDrive -ChildPath 'does-not-exist.dll'

            { Write-BinaryContent -Path $nonExistentPath -Bytes ([byte[]](0x00)) } |
                Should -Throw -ErrorId 'BinaryFileNotFound*'
        }

        It 'Throws when Path targets a directory instead of a file' {
            $path = Join-Path -Path $TestDrive -ChildPath 'target'

            New-Item -Path $path -ItemType Directory -Force | Out-Null

            { Write-BinaryContent -Path $path -Bytes ([byte[]](0x00)) } |
                Should -Throw -ErrorId 'BinaryPathIsDirectory*'
            }
        }

    Context 'Input validation - Bytes' {

        BeforeAll {
            $script:TargetFile = Join-Path -Path $TestDrive -ChildPath 'target.bin'
            [System.IO.File]::WriteAllBytes($script:TargetFile, [byte[]](0x00))
        }

        It 'Throws when Bytes is null' {
            { Write-BinaryContent -Path $script:TargetFile -Bytes $null } |
                Should -Throw
        }

        It 'Throws when Bytes is empty array' {
            { Write-BinaryContent -Path $script:TargetFile -Bytes @() } |
                Should -Throw
        }
    }

    Context 'Successful write - content verification' {

        It 'Writes the exact bytes to the file' {
            $targetFile = Join-Path -Path $TestDrive -ChildPath 'write-exact.bin'
            [byte[]]$bytes = 0x01, 0x02, 0x03, 0x04, 0x05

            [System.IO.File]::WriteAllBytes($targetFile, [byte[]](0x00))

            Write-BinaryContent -Path $targetFile -Bytes $bytes

            [byte[]]$written = [System.IO.File]::ReadAllBytes($targetFile)
            $written | Should -Be $bytes
        }

        It 'Overwrites existing content completely' {
            $targetFile = Join-Path -Path $TestDrive -ChildPath 'overwrite.bin'
            [byte[]]$original = 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
            [byte[]]$newBytes = 0x01, 0x02

            [System.IO.File]::WriteAllBytes($targetFile, $original)

            Write-BinaryContent -Path $targetFile -Bytes $newBytes

            [byte[]]$written = [System.IO.File]::ReadAllBytes($targetFile)
            $written.Count | Should -Be 2
            $written | Should -Be $newBytes
        }

        It 'Writes a single byte correctly' {
            $targetFile = Join-Path -Path $TestDrive -ChildPath 'single-byte.bin'
            [System.IO.File]::WriteAllBytes($targetFile, [byte[]](0x00))

            Write-BinaryContent -Path $targetFile -Bytes ([byte[]](0xAB))

            [byte[]]$written = [System.IO.File]::ReadAllBytes($targetFile)
            $written.Count | Should -Be 1
            $written[0] | Should -Be 0xAB
        }

        It 'Writes a large byte array (1 MB) without error' {
            $targetFile = Join-Path -Path $TestDrive -ChildPath 'large.bin'
            [byte[]]$large = New-Object byte[] (1MB)

            $large[0] = 0xDE
            $large[-1] = 0xAD

            [System.IO.File]::WriteAllBytes($targetFile, [byte[]](0x00))

            Write-BinaryContent -Path $targetFile -Bytes $large

            [byte[]]$written = [System.IO.File]::ReadAllBytes($targetFile)
            $written.Count | Should -Be (1MB)
            $written[0] | Should -Be 0xDE
            $written[-1] | Should -Be 0xAD
        }

        It 'Returns no output (void)' {
            $targetFile = Join-Path -Path $TestDrive -ChildPath 'void-return.bin'
            [System.IO.File]::WriteAllBytes($targetFile, [byte[]](0x00))

            $result = Write-BinaryContent -Path $targetFile -Bytes ([byte[]](0x01, 0x02))

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Idempotence - repeated writes' {

        It 'Produces identical file content on repeated calls' {
            $targetFile = Join-Path -Path $TestDrive -ChildPath 'idempotent.bin'
            [byte[]]$data = 0x10, 0x20, 0x30

            [System.IO.File]::WriteAllBytes($targetFile, [byte[]](0x00))

            Write-BinaryContent -Path $targetFile -Bytes $data
            Write-BinaryContent -Path $targetFile -Bytes $data

            [byte[]]$written = [System.IO.File]::ReadAllBytes($targetFile)
            $written | Should -Be $data
        }
    }

    Context 'Path resolution' {

        It 'Accepts mixed path separators without failure' {
            $targetFile = Join-Path -Path $TestDrive -ChildPath 'resolved.bin'
            [System.IO.File]::WriteAllBytes($targetFile, [byte[]](0x00))

            $mixedPath = $targetFile.Replace('\', '/')

            { Write-BinaryContent -Path $mixedPath -Bytes ([byte[]](0xAB)) } |
                Should -Not -Throw

            [byte[]]$written = [System.IO.File]::ReadAllBytes($targetFile)
            $written[0] | Should -Be 0xAB
        }
    }
}
