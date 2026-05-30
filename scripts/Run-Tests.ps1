<#
.SYNOPSIS
    Runs unit tests for the Infrastructure.Secrets module.

.DESCRIPTION
    Delegates to the canonical implementation in PowerShell-Common
    (expected as a sibling checkout under the same parent directory).

.EXAMPLE
    .\Run-Tests.ps1
#>

# Repo root is one level up now that this script lives under scripts\;
# PowerShell-Common is a sibling of the repo root, so two levels up from here.
$repoRoot = Split-Path -Parent $PSScriptRoot

& ([IO.Path]::Combine($repoRoot, '..', 'PowerShell-Common', '.github', `
    'actions', 'run-unit-tests', 'Run-Tests.ps1')) -TestsRoot $repoRoot
