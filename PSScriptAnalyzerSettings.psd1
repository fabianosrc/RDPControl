﻿@{
    Severity = @('Error', 'Warning')

    IncludeRules = @(
        # Security / Dangerous patterns
        'PSAvoidUsingInvokeExpression',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingComputerNameHardcoded',

        # Bad practices
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingPositionalParameters',
        'PSAvoidUsingWriteHost',
        'PSAvoidDefaultValueSwitchParameter',

        # Cmdlet / function design
        'PSUseApprovedVerbs',
        'PSUseSingularNouns',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUsePSCredentialType',
        'PSUseProcessBlockForPipelineCommand',

        # Type safety / correctness
        'PSUseOutputTypeCorrectly',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseCmdletCorrectly',

        # Compatibility
        'PSUseCompatibleSyntax',
        'PSUseCompatibleTypes',
        'PSUseCompatibleCommands',

        # Documentation
        'PSProvideCommentHelp',

        # Code quality
        'PSReviewUnusedParameter',
        'PSMisleadingBacktick',
        'PSAvoidUsingEmptyCatchBlock'

        # Formatting / style
        'PSUseConsistentIndentation',
        'PSUseConsistentWhitespace',
        'PSAvoidTrailingWhitespace',
        'PSAvoidMultipleEmptyLines',
        'PSAvoidMultipleStatementsPerLine',
        'PSPipelineIndentation',
        'PSUseCorrectCasing',
        'PSHashTableFormatting',

        # Misc
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSMissingModuleManifestField'
    )

    Rules = @{
        # Compatibility configuration
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }

        # Documentation rules
        PSProvideCommentHelp = @{
            Enable                  = $true
            ExportedOnly            = $true
            BlockComment            = $true
            VSCodeSnippetCorrection = $false
            Placement               = 'before'
        }

        # Indentation
        PSUseConsistentIndentation = @{
            IndentationSize = 4
        }

        # Pipeline formatting
        PSPipelineIndentation = @{
            Enable           = $true
            IndentationStyle = 'IncreaseForFirstPipeline'
        }

        # Hashtable formatting
        PSHashTableFormatting = @{
            Enable             = $true
            AlignKeysAndValues = $true
            IndentationSize    = 4
        }
    }

    ExcludeRules = @('TypeNotFound')
}
