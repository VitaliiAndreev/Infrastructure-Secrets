<#
.NOTES
    Dot-sourced by Infrastructure.Secrets.psm1. Module-internal so it
    stays out of the module's public API (and out of the shared
    Module.Tests.ps1 export checks). Operator-facing exposure goes
    through the dedicated runner at scripts\Clear-AllSecrets.ps1
    instead - destructive workstation-maintenance utilities do not
    belong in the importable surface area where a stray
    `Import-Module Infrastructure.Secrets` could surface them by tab
    completion.
#>

function Clear-AllSecrets {
    <#
    .SYNOPSIS
        Removes every secret from every registered SecretManagement vault
        on this workstation, leaving vault registrations in place.

    .DESCRIPTION
        Walks every vault returned by Get-SecretVault, lists every secret
        in each, prompts the operator for a literal "yes" confirmation,
        then deletes them. Vault registrations are NOT removed - only
        their contents. Re-running setup-secrets in each consumer repo
        repopulates the store.

        Secrets stored under Microsoft.PowerShell.SecretStore share a
        single localstore, so the same name may appear in multiple
        registered vault names. Removing through one vault makes the
        second hit on the duplicate report "not found"; that branch is
        handled as a benign skip.

    .PARAMETER Force
        Skip the interactive confirmation. Intended for unattended
        callers (CI cleanup, scripted dev-loop reset). Interactive
        operators should leave it unset.

    .EXAMPLE
        Clear-AllSecrets

        Interactive: lists every (vault, name) pair, prompts for `yes`,
        then deletes.

    .EXAMPLE
        Clear-AllSecrets -Force

        Unattended: deletes without prompting. Use sparingly.
    #>
    [CmdletBinding()]
    param(
        [switch] $Force
    )

    $vaults = Get-SecretVault
    if (-not $vaults) {
        Write-Host 'No vaults registered. Nothing to do.' -ForegroundColor Yellow
        return
    }

    # Collect everything up front so the operator sees the blast radius
    # before any deletion happens.
    $victims = foreach ($v in $vaults) {
        foreach ($s in (Get-SecretInfo -Vault $v.Name -ErrorAction SilentlyContinue)) {
            [PSCustomObject]@{ Vault = $v.Name; Name = $s.Name }
        }
    }

    if (-not $victims) {
        Write-Host 'No secrets present in any vault. Nothing to do.' `
            -ForegroundColor Green
        return
    }

    Write-Host "About to delete $($victims.Count) secret entry/entries:" `
        -ForegroundColor Yellow
    $victims | Sort-Object Vault, Name | Format-Table -AutoSize | Out-Host

    if (-not $Force) {
        $answer = Read-Host "Type 'yes' to confirm (anything else aborts)"
        if ($answer -ne 'yes') {
            Write-Host 'Aborted.' -ForegroundColor Yellow
            return
        }
    }

    $removed = 0
    $failed  = 0
    foreach ($t in $victims) {
        try {
            Remove-Secret -Vault $t.Vault -Name $t.Name -ErrorAction Stop
            Write-Host "[OK] $($t.Vault)/$($t.Name)" -ForegroundColor DarkGray
            $removed++
        }
        catch {
            # Shared-store deletions via a second registered vault land
            # here as "secret not found" - the underlying file already
            # has the entry gone. Treat that as benign; surface anything
            # else as a real failure.
            if ($_.Exception.Message -match 'not found') {
                Write-Host "[skip] $($t.Vault)/$($t.Name) (already gone via shared store)" `
                    -ForegroundColor DarkGray
            }
            else {
                Write-Host "[FAIL] $($t.Vault)/$($t.Name): $($_.Exception.Message)" `
                    -ForegroundColor Red
                $failed++
            }
        }
    }

    Write-Host ''
    Write-Host "Removed: $removed, Failed: $failed" -ForegroundColor Cyan
}
