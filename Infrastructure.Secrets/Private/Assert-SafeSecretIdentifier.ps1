<#
.NOTES
    Do not run this file directly. It is dot-sourced by
    Infrastructure.Secrets.psm1 after the module scope is established.
#>

# ---------------------------------------------------------------------------
# Assert-SafeSecretIdentifier
#   Validates that a vault name or secret name contains only safe characters
#   before it is passed to a provider.
#
#   Allowed: letters, digits, hyphens, underscores, dots.
#   Pattern: ^[A-Za-z0-9_\-\.]+$
#
#   WHY this matters for injection safety:
#     The current SecretStore provider passes $VaultName and $SecretName via
#     PowerShell cmdlet parameter binding, which treats them as literals.
#     However, nothing in the module enforces that future providers do the
#     same. A provider that builds a command string via interpolation or
#     calls an external process would be vulnerable to a caller passing a
#     value such as "; Remove-Item C:\ -Recurse" as a vault name.
#
#     Restricting identifiers to safe characters here, in the dispatcher,
#     means injection via these parameters is impossible regardless of how
#     any current or future provider handles them internally.
#
#   WHY $Value is NOT validated here:
#     Secret values are arbitrary content (JSON, connection strings,
#     certificates, etc.). Restricting their format would break legitimate
#     use cases. Providers are responsible for handling $Value as an opaque
#     string and must never interpolate it into a command string or pass it
#     as an unquoted shell argument.
#
#   Called from Get-InfrastructureSecret and Set-InfrastructureSecret before
#   the provider is invoked.
# ---------------------------------------------------------------------------

function Assert-SafeSecretIdentifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value,

        [Parameter(Mandatory)]
        [string] $ParameterName
    )

    # Deliberately restrictive: only characters that are safe in every
    # known secret backend's identifier space. Tightening later is safe;
    # loosening is not (it may expose backends that were previously safe).
    if ($Value -notmatch '^[A-Za-z0-9_\-\.]+$') {
        throw "$ParameterName '$Value' contains invalid characters. " +
              "Only letters, digits, hyphens, underscores, and dots are allowed."
    }
}
