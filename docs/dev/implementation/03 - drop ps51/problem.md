# Problem: Drop PowerShell 5.1 Support

## Index

- [Context](#context)
- [What Is Changing](#what-is-changing)
- [Why Now](#why-now)
- [Out of Scope](#out-of-scope)

---

## Context

The module manifest (`Infrastructure.Secrets.psd1`) currently declares:

```powershell
PowerShellVersion = '5.1'
```

and pins its only dependency at:

```powershell
RequiredModules = @(
    @{ ModuleName = 'Infrastructure.Common'; ModuleVersion = '1.1.0'; ... }
)
```

However:

- `Infrastructure.Common` has dropped PS 5.1 support and bumped to `2.0.0` (see
  [that repo's implementation 03](../../../../../../../Infrastructure-Common/docs/dev/implementation/03%20-%20drop%20ps51/problem.md)).
  Pinning `1.1.0` here now pulls in the last PS 5.1-era release, diverging from the
  version the rest of the fleet uses.
- The CI unit-test workflow (`ci.yml`) delegates to
  `Infrastructure-Common/.github/workflows/ci-powershell.yml`, which no longer contains
  a PS 5.1 job since that repo's change landed. The fix there propagates automatically;
  only the manifest and docs need updating here.
- No `CompatiblePSEditions` is declared; PSGallery treats the module as Windows-only
  5.1-compatible, which is incorrect.

Unlike `Infrastructure.Common`, this module contains **no PS 5.1 compatibility
compromises in source code** - no `Get-Member` shims, no version-branch comments, no
`$PSVersionTable` guards. The only changes needed are in the manifest and docs.

---

## What Is Changing

| Area | Current state | Target state |
|------|--------------|--------------|
| `Infrastructure.Secrets.psd1` | `PowerShellVersion = '5.1'`, no `CompatiblePSEditions` | `PowerShellVersion = '7.0'`, `CompatiblePSEditions = @('Core')` |
| `Infrastructure.Secrets.psd1` | `RequiredModules` pins `Infrastructure.Common 1.1.0` | Pinned to `2.0.0` (first PS 7-only release) |
| `Infrastructure.Secrets.psd1` | `ModuleVersion = '2.1.0'` | Bumped (breaking change - major bump recommended: `3.0.0`) |
| `README.md` | No explicit PowerShell version requirement stated | "PowerShell 7+" added to requirements |

The CI workflow (`ci.yml`) requires no changes - it inherits the PS 5.1 job removal
from `Infrastructure-Common` automatically.

---

## Why Now

- `Infrastructure.Common 2.0.0` no longer supports PS 5.1. Continuing to declare
  `Infrastructure.Common >= 1.1.0` as the required version would allow PSGallery to
  resolve the dependency to the old PS 5.1-era `1.x` release, undermining the fleet-wide
  upgrade.
- Dropping 5.1 here is a prerequisite for consumer repos to safely use this module on
  the PS 7 runtime all infrastructure scripts target.

---

## Out of Scope

- No source code changes - no PS 5.1 compatibility patterns exist in this repo.
- No test changes - tests are already PS 7-compatible (integration tests run in Docker
  on PS 7 only).
- No `ci.yml` changes - the PS 5.1 job removal propagates from Infrastructure-Common.
