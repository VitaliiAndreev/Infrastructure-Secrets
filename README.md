# Infrastructure-Secrets

Shared PowerShell module for infrastructure secret vault setup and provider-based
runtime read/write across the `Infrastructure-*` polyrepo family.

## Index

- [Overview](#overview)
- [Installation](#installation)
- [Publishing](#publishing)
- [Usage](#usage)
- [API reference](#api-reference)
  - [Initialize-MicrosoftPowerShellSecretStoreVault](#initialize-microsoftpowershellsecretstoreprovidervault)
  - [Use-MicrosoftPowerShellSecretStoreProvider](#use-microsoftpowershellsecretstoreproviderprovider)
  - [Get-InfrastructureSecret](#get-infrastructuresecret)
  - [Set-InfrastructureSecret](#set-infrastructuresecret)
- [Repo structure](#repo-structure)

---

## Overview

Provides two groups of functions:

**Vault setup (one-time, per machine):**
`Initialize-MicrosoftPowerShellSecretStoreVault` handles SecretStore-specific
one-time setup:

- `Microsoft.PowerShell.SecretManagement` + `Microsoft.PowerShell.SecretStore`
  module installation (via `Use-MicrosoftPowerShellSecretStoreProvider`)
- SecretStore configuration and initialisation (non-interactive, AES-256
  encrypted, scoped to the current Windows user account)
- Vault registration
- Secret storage and round-trip verification

Consuming repos call this once per machine from their own thin
`setup-secrets.ps1`, passing only the vault name, secret name, and any
project-specific validation logic.

**Runtime read/write (provider-based):**
`Get-InfrastructureSecret` / `Set-InfrastructureSecret` are thin dispatch
functions that route to whichever backend was registered by a `Use-*Provider`
call. Swapping secret backends requires only changing which `Use-*Provider`
is called; no other code changes.

`Use-MicrosoftPowerShellSecretStoreProvider` registers
`Microsoft.PowerShell.SecretStore` as the active backend - a cross-platform
PowerShell module that stores secrets in an AES-256 / DPAPI-encrypted local
file (scoped to the Windows user account on Windows). It is not the Windows
Credential Manager.

---

## Installation

Consuming repos install automatically from PSGallery - no manual step needed.

To install manually:

```powershell
Install-Module Infrastructure.Secrets -Scope CurrentUser
```

To update an existing installation:

```powershell
Update-Module Infrastructure.Secrets
```

**For local development of this module:** use `Install.ps1` to install from
source instead of PSGallery.

---

## Publishing

Publishing is fully automated via GitHub Actions.

**To ship a new version:**

1. Bump `ModuleVersion` in [Infrastructure.Secrets/Infrastructure.Secrets.psd1](Infrastructure.Secrets/Infrastructure.Secrets.psd1)
2. Open a PR, get it reviewed and merged

On merge, [.github/workflows/tag.yml](.github/workflows/tag.yml) runs CI,
creates a matching git tag, then publishes to PSGallery automatically via
the shared workflow in `Infrastructure-Common`. No manual tagging step required.

**One-time setup:** add your PSGallery API key as a repository secret named
`PSGALLERY_API_KEY` under Settings -> Secrets and variables -> Actions.
Generate a key at [powershellgallery.com/account/apikeys](https://www.powershellgallery.com/account/apikeys).

---

## Usage

A consuming repo's `setup-secrets.ps1` imports the module and calls
`Initialize-MicrosoftPowerShellSecretStoreVault`:

```powershell
Import-Module Infrastructure.Secrets -ErrorAction Stop

Initialize-MicrosoftPowerShellSecretStoreVault `
    -VaultName  'MyVault' `
    -SecretName 'MyConfig' `
    -ConfigFile $ConfigFile `
    -Validate {
        param($json)
        $entries = @($json | ConvertFrom-Json)
        if ($entries.Count -eq 0) { throw 'Config contains no entries.' }
        Write-Host "OK - $($entries.Count) entry/entries validated."
    }
```

The `-Validate` scriptblock is optional. If omitted, the JSON is stored
after a basic parse check only.

To read or write secrets at runtime, register a provider once per session,
then call the dispatch functions:

```powershell
Import-Module Infrastructure.Secrets -ErrorAction Stop

Use-MicrosoftPowerShellSecretStoreProvider

$json  = Get-InfrastructureSecret -VaultName 'MyVault' -SecretName 'MyConfig'
Set-InfrastructureSecret -VaultName 'MyVault' -SecretName 'MyConfig' -Value $json
```

---

## API reference

### `Initialize-MicrosoftPowerShellSecretStoreVault`

| Parameter               | Type        | Required | Description                                                           |
|-------------------------|-------------|----------|-----------------------------------------------------------------------|
| `-VaultName`            | string      | Yes      | SecretStore vault name to register, e.g. `'GHRunners'`               |
| `-SecretName`           | string      | Yes      | Secret name within the vault, e.g. `'GHRunnersConfig'`               |
| `-ConfigFile`           | string      | Yes*     | Path to a JSON file - read at runtime, not modified                   |
| `-ConfigJson`           | string      | Yes*     | Raw JSON string - mutually exclusive with `-ConfigFile`               |
| `-RequireVaultPassword` | switch      | No       | Require an interactive vault password each session (shared machines)  |
| `-Validate`             | scriptblock | No       | Project-specific validation; receives the JSON string; throw to abort |

\* Exactly one of `-ConfigFile` or `-ConfigJson` is required.

Calls `Use-MicrosoftPowerShellSecretStoreProvider` internally, so module
installation and provider registration happen automatically.

---

### `Use-MicrosoftPowerShellSecretStoreProvider`

Registers `Microsoft.PowerShell.SecretStore` as the active provider. Call
once per session before `Get-InfrastructureSecret` or
`Set-InfrastructureSecret`. Safe to call again with the same provider
(idempotent). Throws if a different provider is already registered.

No parameters.

---

### `Get-InfrastructureSecret`

| Parameter     | Type   | Required | Description                        |
|---------------|--------|----------|------------------------------------|
| `-VaultName`  | string | Yes      | Name of the vault to read from     |
| `-SecretName` | string | Yes      | Name of the secret within the vault |

Returns the secret value as a plain-text string. Throws if no provider is
registered or if the secret is not found.

---

### `Set-InfrastructureSecret`

| Parameter     | Type   | Required | Description                                           |
|---------------|--------|----------|-------------------------------------------------------|
| `-VaultName`  | string | Yes      | Name of the vault to write to                         |
| `-SecretName` | string | Yes      | Name of the secret within the vault                   |
| `-Value`      | string | Yes      | Plain-text value; the provider encrypts it at rest    |

Creates the secret if absent; overwrites if present. The value is never
written to any output stream. Throws if no provider is registered.

---

## Repo structure

```
Infrastructure-Secrets/
|- Infrastructure.Secrets/
|  |- Private/
|  |  |- Assert-SafeSecretIdentifier.ps1   # Whitelist-validates vault/secret names
|  |  |- Assert-SecretProviderValid.ps1    # Validates provider hashtable structure
|  |  |- Assert-DispatchPreconditions.ps1  # Shared guard for both dispatchers
|  |  `- Register-SecretProvider.ps1       # ReadOnly enforcement and idempotency
|  |- Public/
|  |  |- Initialize-MicrosoftPowerShellSecretStoreVault.ps1
|  |  |- Get-InfrastructureSecret.ps1
|  |  |- Set-InfrastructureSecret.ps1
|  |  `- Use-MicrosoftPowerShellSecretStoreProvider.ps1
|  |- Infrastructure.Secrets.psm1          # Dot-sources all files; exports functions
|  `- Infrastructure.Secrets.psd1          # Module manifest (version, GUID, exports)
|- Tests/               # Pester unit tests
|- Install.ps1      # Installs from source for local development
|- Publish.ps1      # Publishes to PSGallery (called by CI)
|- Run-Tests.ps1    # Runs Pester tests (called by CI)
`- README.md
```
