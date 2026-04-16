<#
.NOTES
    Do not run this file directly. It is dot-sourced by
    Infrastructure.Secrets.psm1 after the module scope is established.
#>

# ---------------------------------------------------------------------------
# Register-SecretProvider
#   Validates and stores a provider hashtable as the active secret provider,
#   then marks the module variable ReadOnly to prevent accidental overwrite.
#
#   IDEMPOTENCY
#     If the same provider name is already registered, the provider is
#     silently re-registered. This allows setup scripts to be re-run safely.
#
#   MID-SESSION SWAP PREVENTION (not authentication)
#     If a *different* provider name is already registered, the function
#     throws. This prevents accidental backend swaps mid-session, where
#     secrets read from two different stores could be inconsistent.
#     To change providers intentionally, reload the module:
#       Import-Module Infrastructure.Secrets -Force
#     Note: this is not an authenticity check. A caller with PowerShell
#     session access can bypass it. Session access is the trust boundary -
#     no module-level mechanism can defend against arbitrary code execution
#     in the same session.
#
#   READONLY ENFORCEMENT
#     After registration, $Script:SecretProvider is set with -Option ReadOnly.
#     Normal assignment ($Script:SecretProvider = ...) fails with a clear
#     error. Only Set-Variable -Force can override it, which requires
#     deliberate and explicit action - this is the remaining trust boundary.
#
#   Called exclusively by Use-*Provider registration functions.
# ---------------------------------------------------------------------------

function Register-SecretProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Provider
    )

    Assert-SecretProviderValid -Provider $Provider

    $current = $Script:SecretProvider

    if ($null -ne $current) {
        if ($current.Name -ne $Provider.Name) {
            # A different provider is active - require an explicit module
            # reload rather than allowing a silent backend swap.
            throw "Cannot register provider '$($Provider.Name)': " +
                  "provider '$($current.Name)' is already active. " +
                  "Run 'Import-Module Infrastructure.Secrets -Force' to reset."
        }
        # Same provider name - re-registration is idempotent. Remove the
        # ReadOnly flag so the variable can be overwritten with -Force below.
        Set-Variable -Name SecretProvider -Scope Script -Option None -Force
    }

    # Mark ReadOnly after storing so normal assignment ($Script:SecretProvider
    # = ...) raises a clear error instead of silently replacing the provider.
    Set-Variable -Name SecretProvider -Value $Provider `
        -Option ReadOnly -Scope Script -Force
}
