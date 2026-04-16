<#
.SYNOPSIS
    Runs integration tests for the Infrastructure.Secrets module in Docker.

.DESCRIPTION
    Delegates to the canonical implementation in Infrastructure-Common
    (expected as a sibling checkout under the same parent directory).
    Requires Docker Desktop (Linux containers) to be running.

.EXAMPLE
    .\Run-IntegrationTests.ps1
#>

& ([IO.Path]::Combine($PSScriptRoot, '..', 'Infrastructure-Common', '.github', `
    'actions', 'run-integration-tests', 'Run-IntegrationTests.ps1')) -TestsRoot $PSScriptRoot
