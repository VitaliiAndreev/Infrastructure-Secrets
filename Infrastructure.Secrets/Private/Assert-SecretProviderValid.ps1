<#
.NOTES
    Do not run this file directly. It is dot-sourced by
    Infrastructure.Secrets.psm1 after the module scope is established.
#>

# ---------------------------------------------------------------------------
# Assert-SecretProviderValid
#   Validates that a value is a well-formed provider hashtable before it is
#   stored as the active provider or invoked by a dispatcher function.
#
#   A valid provider is a hashtable with three keys:
#     - 'Name': a non-empty string identifying the provider. Used by
#       Register-SecretProvider for idempotency (same name = re-register
#       allowed) and to block accidental mid-session swaps (different name
#       = error). This is NOT an authenticity check - a caller with session
#       access can supply any name. Scriptblock authenticity cannot be
#       verified in PowerShell: the trust boundary is session access itself.
#     - 'Get': a ScriptBlock that reads a secret.
#     - 'Set': a ScriptBlock that writes a secret.
#   Any other shape is rejected with a descriptive error so callers know
#   immediately what is wrong rather than getting a null-dereference or
#   method-not-found error at dispatch time.
#
#   Called from:
#     - Register-SecretProvider: validates before storing, so registration
#       fails loudly rather than silently storing a broken provider.
#     - Get/Set-InfrastructureSecret: validates before invoking, so external
#       code that bypasses Use-*Provider and writes $Script:SecretProvider
#       directly also gets a clear error.
# ---------------------------------------------------------------------------

function Assert-SecretProviderValid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Provider
    )

    if ($null -eq $Provider) {
        throw "Provider is null. Call a Use-*Provider function to register one."
    }

    if ($Provider -isnot [hashtable]) {
        throw "Provider must be a hashtable with 'Get' and 'Set' scriptblock " +
              "keys. Got: $($Provider.GetType().Name)."
    }

    if (-not $Provider.ContainsKey('Name') -or
        [string]::IsNullOrWhiteSpace($Provider['Name'])) {
        throw "Provider hashtable is missing required key 'Name' (non-empty string)."
    }

    foreach ($key in @('Get', 'Set')) {
        if (-not $Provider.ContainsKey($key)) {
            throw "Provider hashtable is missing required key '$key'."
        }
        if ($Provider[$key] -isnot [scriptblock]) {
            throw "Provider key '$key' must be a ScriptBlock. " +
                  "Got: $($Provider[$key].GetType().Name)."
        }
    }
}
