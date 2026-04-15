# Implementation Plan

## Index
- [Step 1 - Provider dispatch](#step-1---provider-dispatch)
- [Step 2 - MicrosoftPowerShellSecretStore provider](#step-2---microsoftpowershellsecretstore-provider)
- [Step 3 - Align vault setup with provider pattern](#step-3---align-vault-setup-with-provider-pattern)
- [Step 4 - Tests](#step-4---tests)

---

## Prerequisites

`Initialize-InfrastructureVault` handles one-time vault setup (see Step 3
for planned rename). These steps cover the runtime read/write path and the
alignment of vault setup naming with the provider pattern.

---

## Step 1 - Provider dispatch

**What:** Module-level provider state, private helpers, and the two public
dispatch functions. All files live under `Infrastructure.Secrets/`:

```
Private/
  Assert-SafeSecretIdentifier.ps1
  Assert-SecretProviderValid.ps1
  Assert-DispatchPreconditions.ps1
  Register-SecretProvider.ps1
Public/
  Get-InfrastructureSecret.ps1
  Set-InfrastructureSecret.ps1
```

### Provider shape

A provider is a hashtable with three mandatory keys:

```powershell
@{
    Name = [string]      # non-empty; used for idempotency and swap detection
    Get  = [scriptblock] # param($VaultName, $SecretName) -> [string]
    Set  = [scriptblock] # param($VaultName, $SecretName, $Value) -> void
}
```

`Name` is not an authenticity check — a caller with session access can
supply any string. It is an idempotency key and an accidental-swap guard.
Scriptblock authenticity cannot be verified in PowerShell; the trust
boundary is session access itself.

### Private helpers

**`Assert-SafeSecretIdentifier`** — validates that `$VaultName` and
`$SecretName` match `^[A-Za-z0-9_\-\.]+$`. Rejects unsafe characters
before they reach any provider, making injection impossible regardless of
how a provider handles the values internally. `$Value` is not validated —
secret content is arbitrary; providers must treat it as an opaque string.

**`Assert-SecretProviderValid`** — validates that `$Script:SecretProvider`
is a non-null hashtable with `Name` (non-empty string), `Get`
(ScriptBlock), and `Set` (ScriptBlock). Catches both the no-provider case
and any malformed value written directly to `$Script:SecretProvider`
outside of a `Use-*Provider` function.

**`Assert-DispatchPreconditions`** — calls both assertions above.
Extracted to avoid duplicating the same two calls in both dispatcher
functions.

**`Register-SecretProvider`** — validates the provider, enforces
idempotency and swap prevention, then stores it as ReadOnly:
- Same `Name` already registered: clears ReadOnly, re-registers
  (idempotent — safe to re-run setup scripts).
- Different `Name` already registered: throws with a reload instruction.
  Changing backends mid-session is not allowed; inconsistency between
  secrets read from two different stores is the risk.
- After storing: marks `$Script:SecretProvider` as `-Option ReadOnly` so
  normal assignment (`$Script:SecretProvider = ...`) fails immediately.
  `Set-Variable -Force` from inside the module scope still works — this
  is the remaining trust boundary.

### Public functions

Both dispatcher functions are intentionally thin:

```powershell
function Get-InfrastructureSecret {
    param([string]$VaultName, [string]$SecretName)
    Assert-DispatchPreconditions -VaultName $VaultName -SecretName $SecretName
    & $Script:SecretProvider.Get $VaultName $SecretName
}

function Set-InfrastructureSecret {
    param([string]$VaultName, [string]$SecretName, [string]$Value)
    Assert-DispatchPreconditions -VaultName $VaultName -SecretName $SecretName
    & $Script:SecretProvider.Set $VaultName $SecretName $Value
}
```

**Why:** All guard logic lives in named private helpers with their own
comments and test surface. The dispatchers stay readable; the helpers stay
independently testable.

```mermaid
graph TD
    subgraph Public["Public"]
        GIS[Get-InfrastructureSecret]
        SIS[Set-InfrastructureSecret]
    end
    subgraph Private["Private"]
        ADP[Assert-DispatchPreconditions]
        ASI[Assert-SafeSecretIdentifier]
        ASV[Assert-SecretProviderValid]
        RSP[Register-SecretProvider]
        SP[$Script:SecretProvider - ReadOnly after first registration]
    end
    subgraph Backend["Backend"]
        B[provider scriptblocks]
    end

    GIS -->|VaultName, SecretName| ADP
    SIS -->|VaultName, SecretName| ADP
    ADP --> ASI
    ADP --> ASV
    ASV --> SP
    GIS -->|dispatches .Get| SP
    SIS -->|dispatches .Set| SP
    SP --> B
    RSP -->|Set-Variable ReadOnly| SP
```

---

## Step 2 - MicrosoftPowerShellSecretStore provider

**What:** One public registration function backed by
`Microsoft.PowerShell.SecretStore` — a cross-platform PowerShell module
that stores secrets in an encrypted local file. On Windows it uses DPAPI,
scoping the encrypted file to the current Windows user account. It is not
the Windows Credential Manager.

The function builds a provider hashtable and passes it to
`Register-SecretProvider`, which handles validation, ReadOnly enforcement,
and idempotency:

```powershell
function Use-MicrosoftPowerShellSecretStoreProvider {
    Register-SecretProvider -Provider @{
        Name = 'MicrosoftPowerShellSecretStore'
        Get  = {
            param($VaultName, $SecretName)
            Get-Secret -Vault $VaultName -Name $SecretName `
                -AsPlainText -ErrorAction Stop
        }
        Set  = {
            param($VaultName, $SecretName, $Value)
            Set-Secret -Vault $VaultName -Name $SecretName `
                -Secret $Value -ErrorAction Stop
        }
    }
}
```

A consumer script calls this once at startup before any
`Get-InfrastructureSecret` / `Set-InfrastructureSecret` calls.

Adding a new backend means adding a new `Use-*Provider` function that
calls `Register-SecretProvider` with its own hashtable. No other code
changes.

**Why:** `Register-SecretProvider` centralises all registration logic —
ReadOnly enforcement, idempotency, swap prevention — so each `Use-*Provider`
function is a thin constructor with no guard duplication.

**Provider contract for future implementations:** `$VaultName`,
`$SecretName`, and `$Value` must be passed to backend cmdlets or processes
via parameter binding, never via string interpolation or
`Invoke-Expression`. `$Value` in particular must be treated as an opaque
string and must never appear in a command argument list visible in
`ps aux` or equivalent.

```mermaid
graph TD
    subgraph Public["Public"]
        USS[Use-MicrosoftPowerShellSecretStoreProvider]
        UAK[Use-AzureKeyVaultProvider ...]
    end
    subgraph Private["Private"]
        RSP[Register-SecretProvider]
        SP[$Script:SecretProvider]
    end

    USS -->|Name + Get + Set hashtable| RSP
    UAK -.->|Name + Get + Set hashtable| RSP
    RSP -->|Set-Variable ReadOnly| SP
```

---

## Step 3 - Align vault setup with provider pattern

**Why:** `Initialize-InfrastructureVault` is SecretStore-specific (installs
SecretManagement + SecretStore, configures SecretStore auth, registers a
vault, stores and verifies a secret). The generic name implies it works with
any backend, which is false and breaks the abstraction's promise. Two
changes fix this:

**Change 1 — Move module installation into
`Use-MicrosoftPowerShellSecretStoreProvider`.**
The function already owns "prepare and register the SecretStore backend";
ensuring the required modules are present is part of that. After this
change, calling `Use-MicrosoftPowerShellSecretStoreProvider` is sufficient
for a consumer that only needs runtime reads/writes on a machine where the
vault is already initialised — no vault-setup code runs.

Steps added before `Register-SecretProvider`:
1. Call `Invoke-ModuleInstall` (from `Infrastructure.Common`) for
   `Microsoft.PowerShell.SecretManagement`.
2. Call `Invoke-ModuleInstall` for `Microsoft.PowerShell.SecretStore`.

`Invoke-ModuleInstall` handles the install-if-absent check and import in
one call. The inline NuGet provider guard currently in
`Initialize-InfrastructureVault` is removed — NuGet is a prerequisite for
`Install-Module` and is handled by the consumer's bootstrap before any
module in this family is loaded.

`Infrastructure.Common` must be declared in `RequiredModules` in
`Infrastructure.Secrets.psd1` so `Invoke-ModuleInstall` is available
inside module function bodies without an explicit import at the call site.

**Change 2 — Rename `Initialize-InfrastructureVault` to
`Initialize-MicrosoftPowerShellSecretStoreVault`.**
The new name is parallel to `Use-MicrosoftPowerShellSecretStoreProvider`
and makes the backend coupling explicit. The function calls
`Use-MicrosoftPowerShellSecretStoreProvider` at the start so module
installation is not duplicated, then continues with SecretStore-specific
vault work: auth configuration, vault registration, secret storage, and
round-trip verification.

Files changed:
- `Public/Use-MicrosoftPowerShellSecretStoreProvider.ps1` — add two
  `Invoke-ModuleInstall` calls before `Register-SecretProvider`.
- Rename `Public/Initialize-InfrastructureVault.ps1` →
  `Public/Initialize-MicrosoftPowerShellSecretStoreVault.ps1`; remove
  NuGet guard and module install loop (now owned by `Use-*Provider`);
  call `Use-MicrosoftPowerShellSecretStoreProvider` at start.
- `Infrastructure.Secrets.psm1` — update dot-source path and export name.
- `Infrastructure.Secrets.psd1` — add `Infrastructure.Common` to
  `RequiredModules`; update `FunctionsToExport`; bump minor version.
- `README.md` — rename everywhere.

```mermaid
graph TD
    subgraph Public["Public"]
        USS[Use-MicrosoftPowerShellSecretStoreProvider]
        IVS[Initialize-MicrosoftPowerShellSecretStoreVault]
    end
    subgraph Modules["Module install - owned by Use-*Provider"]
        NuGet[NuGet provider]
        SM[Microsoft.PowerShell.SecretManagement]
        SS[Microsoft.PowerShell.SecretStore]
    end
    subgraph VaultSetup["Vault setup - owned by Initialize-*"]
        Auth[SecretStore auth config]
        Reg[Register-SecretVault]
        Store[Set-Secret + round-trip verify]
    end
    subgraph Private["Private"]
        RSP[Register-SecretProvider]
        SP[$Script:SecretProvider]
    end

    USS --> NuGet
    USS --> SM
    USS --> SS
    USS -->|Name + Get + Set hashtable| RSP
    RSP -->|Set-Variable ReadOnly| SP
    IVS -->|calls| USS
    IVS --> Auth
    IVS --> Reg
    IVS --> Store
```

---

## Step 4 - Tests

### Existing tests - rename only

`Initialize-InfrastructureVault.Tests.ps1` →
`Initialize-MicrosoftPowerShellSecretStoreVault.Tests.ps1`. The test
`BeforeAll` dot-sources the renamed file; all existing test cases remain
valid. Module install steps move out of the function in Step 3, so any
stubs for `Install-PackageProvider` / `Install-Module` move to the new
`Use-MicrosoftPowerShellSecretStoreProvider` test context in the new file
below.

### New test file

Add `Get-InfrastructureSecret.Tests.ps1`.

**`BeforeAll`** — dot-source all private and public function files; declare
`function Get-Secret { param($Vault, $Name, [switch]$AsPlainText) }` and
`function Set-Secret { param($Vault, $Name, $Secret) }` as stubs (same
pattern as the existing file).

**`BeforeEach`** — reset provider state between tests. Because
`$Script:SecretProvider` is ReadOnly after any registration, a plain
assignment fails. Use `Set-Variable -Force` inside the module scope:

```powershell
BeforeEach {
    & (Get-Module Infrastructure.Secrets) {
        Set-Variable -Name SecretProvider -Value $null -Option None -Force
    }
}
```

**Helper for dispatcher tests** — dispatcher tests need a valid provider
that passes `Assert-SecretProviderValid`. Define a factory inside the
module scope so the hashtable structure is correct:

```powershell
function New-MockProvider {
    param([string]$Name = 'MockProvider', [scriptblock]$GetResult = { 'mock' })
    @{ Name = $Name; Get = $GetResult; Set = {} }
}
```

Register it via `Register-SecretProvider` through the module scope to
respect the ReadOnly mechanism.

**Test cases:**

- `Assert-SafeSecretIdentifier` — valid identifiers pass; identifiers with
  special characters (`;`, `$`, spaces, etc.) throw with a message naming
  the parameter.
- `Assert-SecretProviderValid` — null throws; non-hashtable throws; missing
  `Name` throws; blank `Name` throws; missing `Get`/`Set` throws; wrong
  types for `Get`/`Set` throw; valid hashtable passes.
- `Register-SecretProvider` — first registration succeeds and sets
  ReadOnly; re-registration of same name is idempotent; different name
  throws with reload instruction; direct assignment after registration
  throws (because ReadOnly).
- `Assert-DispatchPreconditions` — unsafe `VaultName` throws; unsafe
  `SecretName` throws; null provider throws; valid inputs with valid
  provider pass. Identifier and provider validation is tested here and
  not repeated in the dispatcher tests below.
- `Get-InfrastructureSecret` — dispatches `.Get` with correct `VaultName`
  and `SecretName` arguments when a valid provider is registered.
- `Set-InfrastructureSecret` — dispatches `.Set` with correct `VaultName`,
  `SecretName`, and `Value` arguments; `$Value` with special characters
  passes (not validated).
- `Use-MicrosoftPowerShellSecretStoreProvider` — calls
  `Invoke-ModuleInstall` for `Microsoft.PowerShell.SecretManagement` and
  `Microsoft.PowerShell.SecretStore` (stub `Invoke-ModuleInstall` and
  assert it was called with the correct `-ModuleName` values); after
  calling, `Get-InfrastructureSecret` dispatches to `Get-Secret` with
  expected `-Vault` and `-Name`; `Set-InfrastructureSecret` dispatches to
  `Set-Secret` with expected arguments.

```mermaid
graph TD
    subgraph Existing["Initialize-MicrosoftPowerShellSecretStoreVault.Tests.ps1 (renamed)"]
        ET[existing tests - dot-source path updated]
    end
    subgraph New["Get-InfrastructureSecret.Tests.ps1 (new)"]
        TH[Helper tests - Assert-SafeSecretIdentifier, Assert-SecretProviderValid, Assert-DispatchPreconditions, Register-SecretProvider]
        TD[Dispatcher tests - dispatch only, no validation re-test]
        TP[Provider tests - Mock Get-Secret / Set-Secret]
    end
    TH -->|unit| PH[private helpers]
    TD -->|Register-SecretProvider via module scope| D[dispatcher functions]
    TP -->|Use-MicrosoftPowerShellSecretStoreProvider then invoke| P[Get/Set-InfrastructureSecret]
```
