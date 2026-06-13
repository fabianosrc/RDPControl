#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Store/Core/Assert-RdpEnvironment.ps1"
    . "$PSScriptRoot/../../../../src/Private/Store/Core/New-StoreAuditRecord.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Test-IsElevated.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Resolve-RdpIdentity.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-RdpErrorCategory.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-RdpMembershipCache.ps1"
    . "$PSScriptRoot/../../../../src/Public/User/Add-RdpUser.ps1"
}

Describe 'Add-RdpUser' {

    BeforeEach {
        Mock Assert-RdpEnvironment { }
        Mock Test-IsElevated { $true }
        Mock New-StoreAuditRecord { }
        Mock Add-LocalGroupMember { }

        Mock Get-RdpMembershipCache {
            $hashSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )

            $hashSet.Add('S-1-5-32-544') | Out-Null
            Write-Output -InputObject $hashSet -NoEnumerate
        }

        Mock Resolve-RdpIdentity {
            param($Identity)

            [PSCustomObject]@{
                OriginalIdentity = $Identity
                IsResolved       = $true
                Sid              = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
                Name             = 'User1'
                Domain           = 'CONTOSO'
                ErrorMessage     = $null
            }
        }
    }

    Context 'Elevation requirement' {

        It 'Throws when not elevated' {
            Mock Test-IsElevated { $false }

            { Add-RdpUser -Identity 'User1' -Confirm:$false } |
                Should -Throw -ErrorId 'ElevationRequired,*'
        }

        It 'Does not call Resolve-RdpIdentity when not elevated' {
            Mock Test-IsElevated { $false }

            { Add-RdpUser -Identity 'User1' -Confirm:$false } | Should -Throw

            Should -Invoke Resolve-RdpIdentity -Times 0
        }
    }

    Context 'Environment validation' {

        It 'Calls Assert-RdpEnvironment exactly once' {
            Add-RdpUser -Identity 'User1' -Confirm:$false | Out-Null

            Should -Invoke Assert-RdpEnvironment -Exactly -Times 1
        }
    }

    Context 'Membership cache validation' {

        It 'Throws a terminating error when the cache is null' {
            Mock Get-RdpMembershipCache { $null }

            { Add-RdpUser -Identity 'User1' -Confirm:$false } |
                Should -Throw -ErrorId 'MembershipCacheInitializationFailed,*'
        }

        It 'Throws a terminating error when the cache is the wrong type' {
            Mock Get-RdpMembershipCache { @('not', 'a', 'hashset') }

            { Add-RdpUser -Identity 'User1' -Confirm:$false } |
                Should -Throw -ErrorId 'MembershipCacheInitializationFailed,*'
        }
    }

    Context 'Unresolvable identity' {

        BeforeEach {
            Mock Resolve-RdpIdentity {
                [PSCustomObject]@{
                    OriginalIdentity = 'DoesNotExist'
                    IsResolved       = $false
                    Sid              = $null
                    Name             = $null
                    Domain           = $null
                    ErrorMessage     = "The identity 'DoesNotExist' could not be found."
                }
            }
        }

        It 'Writes a non-terminating error' {
            $errors = $null

            Add-RdpUser -Identity 'DoesNotExist' -Confirm:$false -ErrorVariable errors -ErrorAction SilentlyContinue | Out-Null

            $errors.Count | Should -BeGreaterThan 0
            $errors[0].FullyQualifiedErrorId | Should -Match '^AddRdpUserIdentityNotResolved'
        }

        It 'Does not call Add-LocalGroupMember' {
            Add-RdpUser -Identity 'DoesNotExist' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

            Should -Invoke Add-LocalGroupMember -Times 0
        }

        It 'Continues processing remaining identities after an unresolved one' {
            Mock Resolve-RdpIdentity {
                param($Identity)

                if ($Identity -eq 'DoesNotExist') {
                    return [PSCustomObject]@{
                        OriginalIdentity = $Identity
                        IsResolved       = $false
                        Sid              = $null
                        Name             = $null
                        Domain           = $null
                        ErrorMessage     = "The identity '$Identity' could not be found."
                    }
                }

                [PSCustomObject]@{
                    OriginalIdentity = $Identity
                    IsResolved       = $true
                    Sid              = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
                    Name             = 'User1'
                    Domain           = 'CONTOSO'
                    ErrorMessage     = $null
                }
            }

            Add-RdpUser -Identity 'DoesNotExist', 'User1' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

            Should -Invoke Add-LocalGroupMember -Times 1
        }
    }

    Context 'Already a member' {

        BeforeEach {
            Mock Resolve-RdpIdentity {
                [PSCustomObject]@{
                    OriginalIdentity = 'Administrators'
                    IsResolved       = $true
                    Sid              = 'S-1-5-32-544'
                    Name             = 'Administrators'
                    Domain           = 'BUILTIN'
                    ErrorMessage     = $null
                }
            }
        }

        It 'Writes a warning and skips' {
            $warnings = $null

            Add-RdpUser -Identity 'Administrators' -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null

            $warnings.Count | Should -BeGreaterThan 0
        }

        It 'Does not call Add-LocalGroupMember' {
            Add-RdpUser -Identity 'Administrators' -Confirm:$false -WarningAction SilentlyContinue | Out-Null

            Should -Invoke Add-LocalGroupMember -Times 0
        }

        It 'Does not write an audit record' {
            Add-RdpUser -Identity 'Administrators' -Confirm:$false -WarningAction SilentlyContinue | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 0
        }
    }

    Context 'New member - successful add' {

        It 'Calls Add-LocalGroupMember with the resolved SID' {
            Add-RdpUser -Identity 'User1' -Confirm:$false | Out-Null

            Should -Invoke Add-LocalGroupMember -Times 1
        }

        It 'Writes an audit record containing the SID' {
            Add-RdpUser -Identity 'User1' -Confirm:$false | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 1
        }
    }

    Context 'Concurrent add (MemberExistsException)' {

        BeforeEach {
            Mock Add-LocalGroupMember {
                throw [Microsoft.PowerShell.Commands.MemberExistsException]::new(
                    'The specified account is already a member of the group.'
                )
            }
        }

        It 'Does not write an audit record' {
            Add-RdpUser -Identity 'User1' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 0
        }
    }

    Context 'ShouldProcess support' {

        It 'Does not call Add-LocalGroupMember when -WhatIf is specified' {
            Add-RdpUser -Identity 'User1' -WhatIf | Out-Null

            Should -Invoke Add-LocalGroupMember -Times 0
        }

        It 'Does not write an audit record when -WhatIf is specified' {
            Add-RdpUser -Identity 'User1' -WhatIf | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 0
        }

        It 'Does not throw when -WhatIf is specified' {
            { Add-RdpUser -Identity 'User1' -WhatIf } | Should -Not -Throw
        }
    }

    Context 'Pipeline input' {

        It 'Accepts an array of identities' {
            Add-RdpUser -Identity 'User1', 'User2' -Confirm:$false | Out-Null

            Should -Invoke Resolve-RdpIdentity -Times 2
        }

        It 'Accepts pipeline input' {
            'User1', 'User2' | Add-RdpUser -Confirm:$false | Out-Null

            Should -Invoke Resolve-RdpIdentity -Times 2
        }

        It 'Accepts pipeline input by property name (Identity from Get-RdpUser-like objects)' {
            $objects = @(
                [PSCustomObject]@{
                    Identity = 'CONTOSO\User1'
                },
                [PSCustomObject]@{
                    Identity = 'CONTOSO\User2'
                }
            )

            $objects | Add-RdpUser -Confirm:$false | Out-Null

            Should -Invoke Resolve-RdpIdentity -Times 2
        }
    }

    Context 'Idempotency across pipeline items' {

        It 'Skips a second identity that resolves to a SID already added in the same invocation' {
            Mock Resolve-RdpIdentity {
                [PSCustomObject]@{
                    OriginalIdentity = 'User1'
                    IsResolved       = $true
                    Sid              = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
                    Name             = 'User1'
                    Domain           = 'CONTOSO'
                    ErrorMessage     = $null
                }
            }

            Add-RdpUser -Identity 'User1', 'User1' -Confirm:$false -WarningAction SilentlyContinue | Out-Null

            Should -Invoke Add-LocalGroupMember -Times 1
        }
    }

    Context 'Error handling' {

        It 'Does not write an audit record on failure' {
            Mock Add-LocalGroupMember {
                throw [System.UnauthorizedAccessException]::new('Access is denied')
            }

            Add-RdpUser -Identity 'User1' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 0
        }
    }
}
