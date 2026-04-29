# Plan: Drop PowerShell 5.1 Support

See [problem.md](problem.md) for context and scope.

## Index

- [Step 1 - Update manifest and docs](#step-1)

---

## Step 1

**Update the module manifest and README. No source or CI changes required.**

Reason: unlike `Infrastructure.Common`, this repo has no PS 5.1 code compromises to
clean up and no CI job to remove (the shared workflow already dropped the PS 5.1 job).
All changes are confined to the manifest and docs, making this a single committable unit.

### Files changed

| File | Change |
|------|--------|
| `Infrastructure.Secrets/Infrastructure.Secrets.psd1` | `PowerShellVersion` 5.1 -> 7.0; add `CompatiblePSEditions = @('Core')`; bump `RequiredModules` Infrastructure.Common to 2.0.0; bump `ModuleVersion` (breaking change - major bump recommended: 3.0.0) |
| `README.md` | Add "PowerShell 7+" requirements section |

### Tests

No new tests. Run `Run-Tests.ps1` under `pwsh` locally to confirm all unit tests still
pass after the manifest change.
