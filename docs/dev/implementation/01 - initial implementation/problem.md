# Problem

## Index
- [Summary](#summary)
- [For laymen](#for-laymen)
- [Detail](#detail)

---

## Summary

Scripts that read secrets call the underlying secret store's cmdlets
directly. If the secret backend changes, every consumer script must be
updated individually. There is no single place to swap the implementation.

---

## For laymen

Right now, every script that needs a password goes and asks the secret
store for it using a specific command that only works with that one store.
If we ever want to use a different kind of secret store, we have to find
and change that command in every single script. This work adds a single
shared function that all scripts use instead — so swapping the store later
means changing one file, not ten.

---

## Detail

### The problem with direct calls

Consumer scripts currently call SecretManagement cmdlets such as
`Get-Secret` directly. These calls are coupled to:

- The cmdlet name and parameter names
- The module that must be installed (`Microsoft.PowerShell.SecretStore` —
  a cross-platform PowerShell module that stores secrets in an encrypted
  local file; on Windows it uses DPAPI, scoping the file to the current
  Windows user account)
- The return type and error behaviour of that specific module

Changing the secret backend (e.g., to a cloud key vault or a different
local store) requires finding and updating every direct call across every
consumer script.

### What needs to happen

Introduce two thin wrapper functions in `Infrastructure.Secrets` that
consumer scripts call instead of the store cmdlets directly:

- `Get-InfrastructureSecret` — reads a named secret from a named vault
  and returns it as a plain-text string.
- `Set-InfrastructureSecret` — writes a plain-text string to a named
  vault under a named secret, creating or overwriting as needed.

The wrappers define the interface. The implementation inside them is the
only thing that changes when the backend changes.

### Constraints

- Must be a drop-in addition — existing `Initialize-InfrastructureVault`
  behaviour is unchanged.
- Consumer scripts must not need to import any additional modules beyond
  `Infrastructure.Secrets`; the wrappers handle any required imports
  internally.
- Both functions must propagate errors as terminating errors so consumers
  do not need to check return values for null.
- Secret values must never be written to the host (no `Write-Host`,
  no verbose output of the value itself).
