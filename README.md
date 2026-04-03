# Infrastructure-Secrets

Shared PowerShell module for infrastructure secret vault setup across the
`Infrastructure-*` polyrepo family.

## Index

- [Overview](#overview)
- [Installation](#installation)
- [Publishing](#publishing)
- [Usage](#usage)
- [API reference](#api-reference)
- [Repo structure](#repo-structure)

---

## Overview

Provides `Initialize-InfrastructureVault` - a single function that handles all
PowerShell SecretManagement boilerplate:

- NuGet provider check
- `Microsoft.PowerShell.SecretManagement` + `Microsoft.PowerShell.SecretStore`
  module installation
- SecretStore configuration and initialisation (non-interactive, AES-256
  encrypted, scoped to the current Windows user account)
- Vault registration
- Secret storage and round-trip verification

Consuming repos call this once per machine from their own thin
`setup-secrets.ps1`, passing only the vault name, secret name, and any
project-specific validation logic.

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

Publishing is automated via GitHub Actions - pushing a version tag triggers
the workflow, which calls `Publish.ps1` using a repository secret.

**To ship a new version:**

1. Bump `ModuleVersion` in [Infrastructure.Secrets/Infrastructure.Secrets.psd1](Infrastructure.Secrets/Infrastructure.Secrets.psd1)
2. Commit and push, then tag:
   ```powershell
   git tag 1.0.1
   git push origin 1.0.1
   ```

The `v*` tag triggers [.github/workflows/publish.yml](.github/workflows/publish.yml),
which publishes to PSGallery automatically.

**One-time setup:** add your PSGallery API key as a repository secret named
`PSGALLERY_API_KEY` under Settings -> Secrets and variables -> Actions.
Generate a key at [powershellgallery.com/account/apikeys](https://www.powershellgallery.com/account/apikeys).

---

## Usage

A consuming repo's `setup-secrets.ps1` imports the module and calls
`Initialize-InfrastructureVault`:

```powershell
Import-Module Infrastructure.Secrets -ErrorAction Stop

Initialize-InfrastructureVault `
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

---

## API reference

### `Initialize-InfrastructureVault`

| Parameter               | Type        | Required | Description                                                           |
|-------------------------|-------------|----------|-----------------------------------------------------------------------|
| `-VaultName`            | string      | Yes      | SecretStore vault name to register, e.g. `'GHRunners'`               |
| `-SecretName`           | string      | Yes      | Secret name within the vault, e.g. `'GHRunnersConfig'`               |
| `-ConfigFile`           | string      | Yes*     | Path to a JSON file - read at runtime, not modified                   |
| `-ConfigJson`           | string      | Yes*     | Raw JSON string - mutually exclusive with `-ConfigFile`               |
| `-RequireVaultPassword` | switch      | No       | Require an interactive vault password each session (shared machines)  |
| `-Validate`             | scriptblock | No       | Project-specific validation; receives the JSON string; throw to abort |

\* Exactly one of `-ConfigFile` or `-ConfigJson` is required.

---

## Repo structure

```
Infrastructure-Secrets/
├── Infrastructure.Secrets/
│   ├── Infrastructure.Secrets.psm1   # Module implementation
│   └── Infrastructure.Secrets.psd1   # Module manifest
├── Install.ps1             # Copies module to user's PS module path
└── README.md
```
