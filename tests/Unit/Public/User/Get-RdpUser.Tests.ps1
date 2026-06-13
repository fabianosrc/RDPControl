#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Store/Core/Assert-RdpEnvironment.ps1"
    . "$PSScriptRoot/../../../../src/Public/User/Get-RdpUser.ps1"
}

Describe 'Get-RdpUser' {

    BeforeEach {
        Mock Assert-RdpEnvironment { }
    }

    Context 'Environment validation' {

        It 'Calls Assert-RdpEnvironment exactly once' {
            Mock Get-LocalGroupMember { @() }

            Get-RdpUser | Out-Null

            Should -Invoke Assert-RdpEnvironment -Exactly -Times 1
        }
    }

    Context 'Empty group' {

        It 'Returns nothing when the group has no members' {
            Mock Get-LocalGroupMember { @() }

            @(Get-RdpUser).Count | Should -Be 0
        }
    }

    Context 'Domain account' {

        BeforeEach {
            Mock Get-LocalGroupMember {
                @(
                    [PSCustomObject]@{
                        Name        = 'CONTOSO\User1'
                        ObjectClass = 'User'
                        SID         = [PSCustomObject]@{ Value = 'S-1-5-21-1111111111-2222222222-3333333333-1001' }
                    }
                )
            }
        }

        It 'Splits domain and name correctly' {
            $result = Get-RdpUser

            $result.Domain | Should -Be 'CONTOSO'
            $result.Name   | Should -Be 'User1'
        }

        It 'Returns Identity as DOMAIN\Name' {
            (Get-RdpUser).Identity | Should -Be 'CONTOSO\User1'
        }

        It 'Returns SID as a string value' {
            (Get-RdpUser).SID | Should -Be 'S-1-5-21-1111111111-2222222222-3333333333-1001'
        }

        It 'Returns ObjectClass as a string' {
            (Get-RdpUser).ObjectClass | Should -Be 'User'
            (Get-RdpUser).ObjectClass | Should -BeOfType [string]
        }
    }

    Context 'Local account' {

        BeforeEach {
            Mock Get-LocalGroupMember {
                @(
                    [PSCustomObject]@{
                        Name        = 'LocalUser1'
                        ObjectClass = 'User'
                        SID         = [PSCustomObject]@{ Value = 'S-1-5-21-1111111111-2222222222-3333333333-2001' }
                    }
                )
            }
        }

        It 'Falls back to COMPUTERNAME as Domain' {
            (Get-RdpUser).Domain | Should -Be $env:COMPUTERNAME
        }

        It 'Returns Name without modification' {
            (Get-RdpUser).Name | Should -Be 'LocalUser1'
        }

        It 'Returns Identity as COMPUTERNAME\Name' {
            (Get-RdpUser).Identity | Should -Be "$env:COMPUTERNAME\LocalUser1"
        }
    }

    Context 'Built-in group' {

        BeforeEach {
            Mock Get-LocalGroupMember {
                @(
                    [PSCustomObject]@{
                        Name        = 'BUILTIN\Administrators'
                        ObjectClass = 'Group'
                        SID         = [PSCustomObject]@{ Value = 'S-1-5-32-544' }
                    }
                )
            }
        }

        It 'Returns ObjectClass as Group' {
            (Get-RdpUser).ObjectClass | Should -Be 'Group'
        }

        It 'Splits BUILTIN domain correctly' {
            $result = Get-RdpUser

            $result.Domain | Should -Be 'BUILTIN'
            $result.Name   | Should -Be 'Administrators'
        }

        It 'Returns Identity as BUILTIN\Administrators' {
            (Get-RdpUser).Identity | Should -Be 'BUILTIN\Administrators'
        }
    }

    Context 'Orphaned SID' {

        BeforeEach {
            Mock Get-LocalGroupMember {
                @(
                    [PSCustomObject]@{
                        Name        = 'S-1-5-21-1111111111-2222222222-3333333333-9999'
                        ObjectClass = 'User'
                        SID         = [PSCustomObject]@{ Value = 'S-1-5-21-1111111111-2222222222-3333333333-9999' }
                    }
                )
            }
        }

        It 'Returns the SID string as Name' {
            (Get-RdpUser -WarningAction SilentlyContinue).Name |
                Should -Be 'S-1-5-21-1111111111-2222222222-3333333333-9999'
        }

        It 'Returns the SID string as Identity' {
            (Get-RdpUser -WarningAction SilentlyContinue).Identity |
                Should -Be 'S-1-5-21-1111111111-2222222222-3333333333-9999'
        }

        It 'Returns $null for Domain' {
            (Get-RdpUser -WarningAction SilentlyContinue).Domain | Should -BeNullOrEmpty
        }

        It 'Returns the SID string for SID' {
            (Get-RdpUser -WarningAction SilentlyContinue).SID |
                Should -Be 'S-1-5-21-1111111111-2222222222-3333333333-9999'
        }

        It 'Writes a warning' {
            Get-RdpUser -WarningAction SilentlyContinue -WarningVariable warnings | Out-Null

            $warnings.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Multiple members' {

        BeforeEach {
            Mock Get-LocalGroupMember {
                @(
                    [PSCustomObject]@{
                        Name        = 'BUILTIN\Administrators'
                        ObjectClass = 'Group'
                        SID         = [PSCustomObject]@{ Value = 'S-1-5-32-544' }
                    },
                    [PSCustomObject]@{
                        Name        = 'CONTOSO\User1'
                        ObjectClass = 'User'
                        SID         = [PSCustomObject]@{ Value = 'S-1-5-21-1111111111-2222222222-3333333333-1001' }
                    },
                    [PSCustomObject]@{
                        Name        = 'LocalUser1'
                        ObjectClass = 'User'
                        SID         = [PSCustomObject]@{ Value = 'S-1-5-21-1111111111-2222222222-3333333333-2001' }
                    }
                )
            }
        }

        It 'Returns one object per member' {
            @(Get-RdpUser).Count | Should -Be 3
        }

        It 'Returns distinct Identity values for each member' {
            $identities = (Get-RdpUser).Identity

            ($identities | Select-Object -Unique).Count | Should -Be 3
        }
    }

    Context 'Error handling' {

        It 'Throws a terminating error when Get-LocalGroupMember fails' {
            Mock Get-LocalGroupMember { throw 'Group not found' }

            { Get-RdpUser } | Should -Throw -ErrorId 'GetRdpUserFailed,*'
        }
    }

    Context 'Return contract' {

        BeforeEach {
            Mock Get-LocalGroupMember {
                @(
                    [PSCustomObject]@{
                        Name        = 'CONTOSO\User1'
                        ObjectClass = 'User'
                        SID         = [PSCustomObject]@{ Value = 'S-1-5-21-1111111111-2222222222-3333333333-1001' }
                    }
                )
            }
        }

        It 'Returns PSCustomObject' {
            (Get-RdpUser) | Should -BeOfType PSCustomObject
        }

        It 'Contains all required properties' {
            $result = Get-RdpUser

            $result.PSObject.Properties.Name | Should -Contain 'Identity'
            $result.PSObject.Properties.Name | Should -Contain 'Name'
            $result.PSObject.Properties.Name | Should -Contain 'Domain'
            $result.PSObject.Properties.Name | Should -Contain 'ObjectClass'
            $result.PSObject.Properties.Name | Should -Contain 'SID'
        }
    }
}
