<#
.NOTES
    Do not run this file directly. It is dot-sourced by
    Infrastructure.Secrets.psm1 after the module scope is established.
#>

# ---------------------------------------------------------------------------
# Assert-DispatchPreconditions
#   Shared guard called by Get-InfrastructureSecret and
#   Set-InfrastructureSecret before dispatching to the active provider.
#
#   Checks in order:
#     1. VaultName and SecretName contain only safe characters - prevents
#        injection if a provider passes them to an external process or builds
#        a command string via interpolation.
#     2. The active provider is a well-formed hashtable - catches both the
#        no-provider case and any malformed value written directly to
#        $Script:SecretProvider outside of a Use-*Provider function.
#
#   $Value (the secret content) is intentionally not validated here.
#   Secret values are arbitrary strings; restricting their format would
#   break legitimate use cases. Providers must treat $Value as opaque and
#   must never interpolate it into a command string.
# ---------------------------------------------------------------------------

function Assert-DispatchPreconditions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $VaultName,

        [Parameter(Mandatory)]
        [string] $SecretName
    )

    Assert-SafeSecretIdentifier -Value $VaultName  -ParameterName 'VaultName'
    Assert-SafeSecretIdentifier -Value $SecretName -ParameterName 'SecretName'
    Assert-SecretProviderValid  -Provider $Script:SecretProvider
}
