<#
.SYNOPSIS
    Runs unit tests for the Infrastructure.Secrets module.

.DESCRIPTION
    Delegates to the canonical implementation in Infrastructure-Common
    (expected as a sibling checkout under the same parent directory).

.EXAMPLE
    .\Run-Tests.ps1
#>

& ([IO.Path]::Combine($PSScriptRoot, '..', 'Infrastructure-Common', '.github', `
    'actions', 'run-unit-tests', 'Run-Tests.ps1')) -TestsRoot $PSScriptRoot
