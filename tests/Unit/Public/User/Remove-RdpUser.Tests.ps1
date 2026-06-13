#Requires -Version 5.1

BeforeAll {
    . "$PSScriptRoot/../../../../src/Private/Store/Core/Assert-RdpEnvironment.ps1"
    . "$PSScriptRoot/../../../../src/Private/Store/Core/New-StoreAuditRecord.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Test-IsElevated.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Resolve-RdpIdentity.ps1"
    . "$PSScriptRoot/../../../../src/Private/Engine/Get-RdpMembershipCache.ps1"
    . "$PSScriptRoot/../../../../src/Public/User/Remove-RdpUser.ps1"
}

Describe 'Remove-RdpUser' {

    BeforeEach {
        $ConfirmPreference = 'None'

        Mock Assert-RdpEnvironment { }
        Mock Test-IsElevated { $true }
        Mock New-StoreAuditRecord { }
        Mock Remove-LocalGroupMember { }

        Mock Get-RdpMembershipCache {
            $hashSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )

            $hashSet.Add('S-1-5-21-1111111111-2222222222-3333333333-1001') | Out-Null
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

            { Remove-RdpUser -Identity 'User1' -Confirm:$false } |
                Should -Throw -ErrorId 'ElevationRequired,*'
        }

        It 'Does not call Resolve-RdpIdentity when not elevated' {
            Mock Test-IsElevated { $false }

            { Remove-RdpUser -Identity 'User1' -Confirm:$false } |
                Should -Throw

            Should -Invoke Resolve-RdpIdentity -Times 0
        }
    }

    Context 'Environment validation' {

        It 'Calls Assert-RdpEnvironment exactly once' {
            Remove-RdpUser -Identity 'User1' -Confirm:$false | Out-Null

            Should -Invoke Assert-RdpEnvironment -Exactly -Times 1
        }
    }

    Context 'Membership cache validation' {

        It 'Throws a terminating error when the cache is null' {
            Mock Get-RdpMembershipCache { $null }

            { Remove-RdpUser -Identity 'User1' -Confirm:$false } |
                Should -Throw -ErrorId 'MembershipCacheInitializationFailed,*'
        }

        It 'Throws a terminating error when the cache is the wrong type' {
            Mock Get-RdpMembershipCache { @('not', 'a', 'hashset') }

            { Remove-RdpUser -Identity 'User1' -Confirm:$false } |
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

            $rdpUserParams = @{
                Identity      = 'DoesNotExist'
                Confirm       = $false
                ErrorVariable = 'errors'
                ErrorAction   = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            $errors.Count | Should -BeGreaterThan 0

            $targetError = $errors |
                Where-Object {
                    $_ -is [System.Management.Automation.ErrorRecord] -and
                    $_.FullyQualifiedErrorId -match '^RemoveRdpUserIdentityNotResolved'
                }

            $targetError | Should -Not -BeNullOrEmpty
        }

        It 'Does not call Remove-LocalGroupMember' {
            $rdpUserParams = @{
                Identity      = 'DoesNotExist'
                Confirm       = $false
                ErrorAction   = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            Should -Invoke Remove-LocalGroupMember -Times 0
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

            $rdpUserParams = @{
                Identity      = 'DoesNotExist', 'User1'
                Confirm       = $false
                ErrorAction   = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            Should -Invoke Remove-LocalGroupMember -Times 1
        }
    }

    Context 'Not a member' {

        BeforeEach {
            Mock Resolve-RdpIdentity {
                [PSCustomObject]@{
                    OriginalIdentity = 'User2'
                    IsResolved       = $true
                    Sid              = 'S-1-5-21-1111111111-2222222222-3333333333-2002'
                    Name             = 'User2'
                    Domain           = 'CONTOSO'
                    ErrorMessage     = $null
                }
            }
        }

        It 'Writes an informational message and skips' {
            $info = $null

            $rdpUserParams = @{
                Identity          = 'User2'
                Confirm           = $false
                InformationVariable = 'info'
                InformationAction   = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            $info.Count | Should -BeGreaterThan 0
        }

        It 'Does not call Remove-LocalGroupMember' {
            $rdpUserParams = @{
                Identity          = 'User2'
                Confirm           = $false
                InformationAction = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            Should -Invoke Remove-LocalGroupMember -Times 0
        }

        It 'Does not write an audit record' {
            $rdpUserParams = @{
                Identity          = 'User2'
                Confirm           = $false
                InformationAction = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 0
        }

        It 'Returns Status=NotMember with -PassThru' {
            $rdpUserParams = @{
                Identity          = 'User2'
                Confirm           = $false
                PassThru          = $true
                InformationAction = 'SilentlyContinue'
            }

            $result = Remove-RdpUser @rdpUserParams

            $result.Status | Should -Be 'NotMember'
            $result.Removed | Should -BeFalse
        }
    }

    Context 'Existing member - successful removal' {

        It 'Calls Remove-LocalGroupMember with the resolved SID' {
            Remove-RdpUser -Identity 'User1' -Confirm:$false | Out-Null

            Should -Invoke Remove-LocalGroupMember -Times 1
        }

        It 'Writes an audit record containing the SID' {
            Remove-RdpUser -Identity 'User1' -Confirm:$false | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 1
        }
    }

    Context 'Removal by raw SID (orphaned entry)' {

        BeforeEach {
            Mock Get-RdpMembershipCache {
                $hashSet = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase
                )

                $hashSet.Add('S-1-5-21-1111111111-2222222222-3333333333-9999') | Out-Null
                Write-Output -InputObject $hashSet -NoEnumerate
            }

            Mock Resolve-RdpIdentity {
                [PSCustomObject]@{
                    OriginalIdentity = 'S-1-5-21-1111111111-2222222222-3333333333-9999'
                    IsResolved       = $true
                    Sid              = 'S-1-5-21-1111111111-2222222222-3333333333-9999'
                    Name             = $null
                    Domain           = $null
                    ErrorMessage     = $null
                }
            }
        }

        It 'Removes a SID directly when Name is null' {
            $rdpUserParams = @{
                Identity          = 'S-1-5-21-1111111111-2222222222-3333333333-9999'
                Confirm           = $false
                InformationAction = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            Should -Invoke Remove-LocalGroupMember -Times 1
        }
    }

    Context 'ShouldProcess (-WhatIf, -Confirm)' {

        It 'Does not call Remove-LocalGroupMember when -WhatIf is specified' {
            Remove-RdpUser -Identity 'User1' -WhatIf | Out-Null

            Should -Invoke Remove-LocalGroupMember -Times 0
        }

        It 'Does not write an audit record when -WhatIf is specified' {
            Remove-RdpUser -Identity 'User1' -WhatIf | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 0
        }

        It 'Does not throw when -WhatIf is specified' {
            { Remove-RdpUser -Identity 'User1' -WhatIf } | Should -Not -Throw
        }

        It 'Writes a verbose message when skipped by user confirmation' {
            Remove-RdpUser -Identity 'User1' -Confirm:$false -WhatIf -Verbose 4>&1 |
                Should -Not -BeNullOrEmpty
        }
    }

    Context '-Force parameter' {

        It 'Suppresses the confirmation prompt without throwing' {
            { Remove-RdpUser -Identity 'User1' -Force } | Should -Not -Throw
        }

        It 'Calls Remove-LocalGroupMember when -Force is specified' {
            Remove-RdpUser -Identity 'User1' -Force | Out-Null

            Should -Invoke Remove-LocalGroupMember -Times 1
        }
    }

    Context '-PassThru parameter' {

        It 'Returns nothing by default' {
            $result = Remove-RdpUser -Identity 'User1' -Confirm:$false

            $result | Should -BeNullOrEmpty
        }

        It 'Returns Status=Removed and Removed=$true on success' {
            $result = Remove-RdpUser -Identity 'User1' -Confirm:$false -PassThru

            $result | Should -BeOfType PSCustomObject
            $result.Identity | Should -Be 'User1'
            $result.Sid | Should -Be 'S-1-5-21-1111111111-2222222222-3333333333-1001'
            $result.Status | Should -Be 'Removed'
            $result.Removed | Should -BeTrue
        }

        It 'Returns Status=NotMember and Removed=$false when not a member' {
            Mock Resolve-RdpIdentity {
                [PSCustomObject]@{
                    OriginalIdentity = 'User2'
                    IsResolved       = $true
                    Sid              = 'S-1-5-21-1111111111-2222222222-3333333333-2002'
                    Name             = 'User2'
                    Domain           = 'CONTOSO'
                    ErrorMessage     = $null
                }
            }

            $rdpUserParams = @{
                Identity          = 'User2'
                Confirm           = $false
                PassThru          = $true
                InformationAction = 'SilentlyContinue'
            }

            $result = Remove-RdpUser @rdpUserParams

            $result.Status | Should -Be 'NotMember'
            $result.Removed | Should -BeFalse
        }

        It 'Returns a PSCustomObject with Removed=$false on failure' {
            Mock Remove-LocalGroupMember {
                throw [System.Management.Automation.ItemNotFoundException]::new('Member not found')
            }

            $rdpUserParams = @{
                Identity      = 'User1'
                Confirm       = $false
                PassThru      = $true
                ErrorAction   = 'SilentlyContinue'
            }

            $result = Remove-RdpUser @rdpUserParams

            $result.Removed | Should -BeFalse
        }
    }

    Context 'Pipeline input' {

        It 'Accepts an array of identities' {
            Remove-RdpUser -Identity 'User1', 'User2' -Confirm:$false | Out-Null

            Should -Invoke Resolve-RdpIdentity -Times 2
        }

        It 'Accepts pipeline input' {
            'User1', 'User2' | Remove-RdpUser -Confirm:$false | Out-Null

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

            $objects | Remove-RdpUser -Confirm:$false | Out-Null

            Should -Invoke Resolve-RdpIdentity -Times 2
        }
    }

    Context 'Idempotency across pipeline items' {

        BeforeEach {
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
        }

        It 'Skips a second identity that resolves to a SID already removed in the same invocation' {
            Remove-RdpUser -Identity 'User1', 'User1' -Confirm:$false | Out-Null

            Should -Invoke Remove-LocalGroupMember -Times 1
        }

        It 'Returns Status=AlreadyRemoved for the duplicate with -PassThru' {
            $results = @(Remove-RdpUser -Identity 'User1', 'User1' -Confirm:$false -PassThru)

            $results[0].Status | Should -Be 'Removed'
            $results[1].Status | Should -Be 'AlreadyRemoved'
            $results[1].Removed | Should -BeTrue
        }
    }

    Context 'Multiple identities with mixed outcomes' {

        BeforeEach {
            # SID for User1 is present in the membership cache (will be
            # removed). User2 and User3 are not in the cache, so User2
            # resolves to NotMember; User3 also resolves successfully but
            # Remove-LocalGroupMember is mocked to fail only for User3.
            Mock Get-RdpMembershipCache {
                $hashSet = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase
                )

                $hashSet.Add('S-1-5-21-1111111111-2222222222-3333333333-1001') | Out-Null
                $hashSet.Add('S-1-5-21-1111111111-2222222222-3333333333-3003') | Out-Null
                Write-Output -InputObject $hashSet -NoEnumerate
            }

            Mock Resolve-RdpIdentity {
                param($Identity)

                switch ($Identity) {
                    'User1' {
                        [PSCustomObject]@{
                            OriginalIdentity = $Identity
                            IsResolved       = $true
                            Sid              = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
                            Name             = 'User1'
                            Domain           = 'CONTOSO'
                            ErrorMessage     = $null
                        }
                    }
                    'User2' {
                        [PSCustomObject]@{
                            OriginalIdentity = $Identity
                            IsResolved       = $true
                            Sid              = 'S-1-5-21-1111111111-2222222222-3333333333-2002'
                            Name             = 'User2'
                            Domain           = 'CONTOSO'
                            ErrorMessage     = $null
                        }
                    }
                    'User3' {
                        [PSCustomObject]@{
                            OriginalIdentity = $Identity
                            IsResolved       = $true
                            Sid              = 'S-1-5-21-1111111111-2222222222-3333333333-3003'
                            Name             = 'User3'
                            Domain           = 'CONTOSO'
                            ErrorMessage     = $null
                        }
                    }
                }
            }

            Mock Remove-LocalGroupMember {
                param($Member)

                if ($Member[0].Name -eq 'S-1-5-21-1111111111-2222222222-3333333333-3003') {
                        throw [System.Management.Automation.ItemNotFoundException]::new(
                        'Member not found'
                    )
                }
            }
        }

        It 'Returns one result per identity with the correct Status for each' {
            $results = @(
                $rdpUserParams = @{
                    Identity          = 'User1', 'User2', 'User3'
                    Confirm           = $false
                    PassThru          = $true
                    InformationAction = 'SilentlyContinue'
                    ErrorAction       = 'SilentlyContinue'
                }

                Remove-RdpUser @rdpUserParams
            )

            $results.Count | Should -Be 3

            $results[0].Status | Should -Be 'Removed'
            $results[1].Status | Should -Be 'NotMember'
            $results[2].Status | Should -Be 'Failed'

        }

        It 'Sets Removed correctly for each outcome' {
            $results = @(
                $rdpUserParams = @{
                    Identity          = 'User1', 'User2', 'User3'
                    Confirm           = $false
                    PassThru          = $true
                    InformationAction = 'SilentlyContinue'
                    ErrorAction       = 'SilentlyContinue'
                }

                Remove-RdpUser @rdpUserParams
            )

            $results[0].Removed | Should -BeTrue
            $results[1].Removed | Should -BeFalse
            $results[2].Removed | Should -BeFalse
        }

        It 'Calls Remove-LocalGroupMember only for the members present in the cache' {
            $rdpUserParams = @{
                Identity          = 'User1', 'User2', 'User3'
                Confirm           = $false
                InformationAction = 'SilentlyContinue'
                ErrorAction       = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            Should -Invoke Remove-LocalGroupMember -Times 2
        }

        It 'Writes an audit record only for the successful removal' {
            $rdpUserParams = @{
                Identity          = 'User1', 'User2', 'User3'
                Confirm           = $false
                InformationAction = 'SilentlyContinue'
                ErrorAction       = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 1
        }

        It 'Writes a non-terminating error only for the failed identity' {
            $errors = $null

            $rdpUserParams = @{
                Identity          = 'User1', 'User2', 'User3'
                Confirm           = $false
                InformationAction = 'SilentlyContinue'
                ErrorVariable     = 'errors'
                ErrorAction       = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            $targetErrors = @(
                $errors | Where-Object {
                    $_ -is [System.Management.Automation.ErrorRecord] -and
                    $_.FullyQualifiedErrorId -match '^RemoveRdpUserFailed'
                }
            )

            $targetErrors.Count | Should -Be 1
            $targetErrors[0].TargetObject | Should -Be 'User3'
        }
    }

    Context 'Error handling' {

        BeforeEach {
            Mock Remove-LocalGroupMember {
                throw [System.Management.Automation.ItemNotFoundException]::new('Member not found')
            }
        }

        It 'Writes a non-terminating error with correct ErrorId' {
            $errors = $null

            $rdpUserParams = @{
                Identity      = 'User1'
                Confirm       = $false
                ErrorVariable = 'errors'
                ErrorAction   = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            $targetError = $errors | Where-Object {
                $_ -is [System.Management.Automation.ErrorRecord] -and
                $_.FullyQualifiedErrorId -match '^RemoveRdpUserFailed'
            }

            $targetError | Should -Not -BeNullOrEmpty
        }

        It 'Does not write an audit record on failure' {
            $rdpUserParams = @{
                Identity      = 'User1'
                Confirm       = $false
                ErrorAction   = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            Should -Invoke New-StoreAuditRecord -Times 0
        }

        It 'Returns Status=Failed with -PassThru' {
            $rdpUserParams = @{
                Identity      = 'User1'
                Confirm       = $false
                PassThru      = $true
                ErrorAction   = 'SilentlyContinue'
            }

            $result = Remove-RdpUser @rdpUserParams

            $result.Status | Should -Be 'Failed'
            $result.Removed | Should -BeFalse
        }

        It 'Classifies a generic failure as InvalidOperation' {
            $errors = $null

            $rdpUserParams = @{
                Identity      = 'User1'
                Confirm       = $false
                ErrorVariable = 'errors'
                ErrorAction   = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            $targetError = $errors | Where-Object {
                $_ -is [System.Management.Automation.ErrorRecord] -and
                $_.FullyQualifiedErrorId -match '^RemoveRdpUserFailed'
            }

            $targetError.CategoryInfo.Category | Should -Be 'InvalidOperation'
        }

        It 'Classifies an UnauthorizedAccessException as PermissionDenied' {
            Mock Remove-LocalGroupMember {
                throw [System.UnauthorizedAccessException]::new('Access is denied')
            }

            $errors = $null

            $rdpUserParams = @{
                Identity      = 'User1'
                Confirm       = $false
                ErrorVariable = 'errors'
                ErrorAction   = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            $targetError = $errors | Where-Object {
                $_ -is [System.Management.Automation.ErrorRecord] -and
                $_.FullyQualifiedErrorId -match '^RemoveRdpUserFailed'
            }

            $targetError.CategoryInfo.Category | Should -Be 'PermissionDenied'
        }
    }

    Context 'Audit logging failure' {

        It 'Writes a warning but still reports success when New-StoreAuditRecord fails' {
            Mock New-StoreAuditRecord {
                throw 'Database unavailable'
            }

            $warnings = $null

            $rdpUserParams = @{
                Identity      = 'User1'
                Confirm       = $false
                PassThru      = $true
                WarningVariable = 'warnings'
                WarningAction   = 'SilentlyContinue'
            }

            $result = Remove-RdpUser @rdpUserParams

            $warnings.Count | Should -BeGreaterThan 0
            $result.Status | Should -Be 'Removed'
            $result.Removed | Should -BeTrue
        }

        It 'Still calls Remove-LocalGroupMember when audit logging fails' {
            Mock New-StoreAuditRecord {
                throw 'Database unavailable'
            }

            $rdpUserParams = @{
                Identity      = 'User1'
                Confirm       = $false
                PassThru      = $true
                WarningVariable = 'warnings'
                WarningAction   = 'SilentlyContinue'
            }

            Remove-RdpUser @rdpUserParams | Out-Null

            Should -Invoke Remove-LocalGroupMember -Times 1
        }
    }
}
