#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-RegistryValue.ps1"

    # Mount a temporary in-memory registry hive for all tests
    $Script:TestHive = 'HKCU:\SOFTWARE\RDPControl_Tests'
    New-Item -Path $Script:TestHive -Force | Out-Null

    # Populate with known values
    New-ItemProperty -Path $Script:TestHive -Name 'DWordValue'  -Value 3389    -PropertyType DWord  -Force | Out-Null
    New-ItemProperty -Path $Script:TestHive -Name 'StringValue' -Value 'hello' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $Script:TestHive -Name 'ZeroValue'   -Value 0       -PropertyType DWord  -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $Script:TestHive -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-RegistryValue' {

    Context 'Key does not exist — without -Strict' {

        It 'Returns $null when key does not exist' {
            $result = Get-RegistryValue -Path 'HKCU:\SOFTWARE\DoesNotExist_RDPControl' -Name 'AnyValue'
            $result | Should -BeNullOrEmpty
        }

        It 'Does not throw when key does not exist' {
            { Get-RegistryValue -Path 'HKCU:\SOFTWARE\DoesNotExist_RDPControl' -Name 'AnyValue' } |
                Should -Not -Throw
        }
    }

    Context 'Key does not exist — with -Strict' {

        It 'Throws RegistryKeyNotFound when key does not exist' {
            { Get-RegistryValue -Path 'HKCU:\SOFTWARE\DoesNotExist_RDPControl' -Name 'AnyValue' -Strict } |
                Should -Throw -ErrorId 'RegistryKeyNotFound,Get-RegistryValue'
        }
    }

    Context 'Key exists but value does not — without -Strict' {

        It 'Returns $null when value does not exist' {
            $result = Get-RegistryValue -Path $Script:TestHive -Name 'NonExistentValue'
            $result | Should -BeNullOrEmpty
        }

        It 'Does not throw when value does not exist' {
            { Get-RegistryValue -Path $Script:TestHive -Name 'NonExistentValue' } |
                Should -Not -Throw
        }
    }

    Context 'Key exists but value does not — with -Strict' {

        It 'Throws RegistryValueNotFound when value does not exist' {
            { Get-RegistryValue -Path $Script:TestHive -Name 'NonExistentValue' -Strict } |
                Should -Throw -ErrorId 'RegistryValueNotFound,Get-RegistryValue'
        }
    }

    Context 'Successful read' {

        It 'Returns the correct DWord value' {
            $result = Get-RegistryValue -Path $Script:TestHive -Name 'DWordValue'
            $result | Should -Be 3389
        }

        It 'Returns the correct String value' {
            $result = Get-RegistryValue -Path $Script:TestHive -Name 'StringValue'
            $result | Should -Be 'hello'
        }

        It 'Returns 0 correctly (not confused with $null)' {
            $result = Get-RegistryValue -Path $Script:TestHive -Name 'ZeroValue'
            $result | Should -Be 0
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Does not throw for a valid key and value' {
            { Get-RegistryValue -Path $Script:TestHive -Name 'DWordValue' } |
                Should -Not -Throw
        }
    }

    Context '-Strict with existing key and value' {

        It 'Returns the value without throwing when -Strict and value exists' {
            $result = Get-RegistryValue -Path $Script:TestHive -Name 'DWordValue' -Strict
            $result | Should -Be 3389
        }
    }

    Context 'Return type' {

        It 'Returns an Int32 for a DWord registry value' {
            $result = Get-RegistryValue -Path $Script:TestHive -Name 'DWordValue'
            $result | Should -BeOfType [int]
        }

        It 'Returns a String for a String registry value' {
            $result = Get-RegistryValue -Path $Script:TestHive -Name 'StringValue'
            $result | Should -BeOfType [string]
        }
    }
}
