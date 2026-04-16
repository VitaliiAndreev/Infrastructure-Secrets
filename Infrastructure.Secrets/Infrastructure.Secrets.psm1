<#
.SYNOPSIS
    Shared PowerShell module for infrastructure secret management.

.DESCRIPTION
    Provides two groups of functions:

    Vault setup (one-time, per machine):
      Initialize-MicrosoftPowerShellSecretStoreVault - configures
      SecretStore, registers a local vault, and stores a JSON config
      secret. Calls Use-MicrosoftPowerShellSecretStoreProvider internally
      so module installation is not duplicated.

    Runtime read/write (provider-based):
      Get-InfrastructureSecret / Set-InfrastructureSecret - thin dispatch
      layer that routes to whichever provider was registered by a
      Use-*Provider call. Swapping secret backends requires only changing
      which Use-*Provider is called; no other code changes.

      Use-MicrosoftPowerShellSecretStoreProvider - registers the
      Microsoft.PowerShell.SecretStore backend (encrypted local file,
      DPAPI-scoped to the Windows user account on Windows).

    Each public function lives in its own file under Public\ and is
    dot-sourced below, so diffs stay focused on a single function per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-level provider state. Holds the hashtable registered by the most
# recent Use-*Provider call. $null until a provider is registered.
# Get-InfrastructureSecret and Set-InfrastructureSecret read this variable;
# Use-*Provider functions write it.
$Script:SecretProvider = $null

. "$PSScriptRoot\Private\Assert-SafeSecretIdentifier.ps1"
. "$PSScriptRoot\Private\Assert-SecretProviderValid.ps1"
. "$PSScriptRoot\Private\Assert-DispatchPreconditions.ps1"
. "$PSScriptRoot\Private\Register-SecretProvider.ps1"

. "$PSScriptRoot\Public\Initialize-MicrosoftPowerShellSecretStoreVault.ps1"
. "$PSScriptRoot\Public\Get-InfrastructureSecret.ps1"
. "$PSScriptRoot\Public\Set-InfrastructureSecret.ps1"
. "$PSScriptRoot\Public\Use-MicrosoftPowerShellSecretStoreProvider.ps1"

Export-ModuleMember -Function @(
    'Initialize-MicrosoftPowerShellSecretStoreVault'
    'Get-InfrastructureSecret'
    'Set-InfrastructureSecret'
    'Use-MicrosoftPowerShellSecretStoreProvider'
)
