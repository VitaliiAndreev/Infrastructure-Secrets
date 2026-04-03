<#
.SYNOPSIS
    Shared PowerShell module for infrastructure secret vault setup.

.DESCRIPTION
    Provides Initialize-InfrastructureVault: a single function that handles all
    SecretManagement boilerplate - NuGet provider, module installation,
    SecretStore configuration, vault registration, and secret storage.

    Consuming repos call this once per machine from their own thin
    setup-secrets.ps1, passing only the project-specific vault name,
    secret name, and optional validation logic.

    Each public function lives in its own file under Public\ and is
    dot-sourced below, so diffs stay focused on a single function per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Public\Initialize-InfrastructureVault.ps1"

Export-ModuleMember -Function Initialize-InfrastructureVault
