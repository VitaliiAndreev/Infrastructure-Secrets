function Set-InfrastructureSecret {
    <#
    .SYNOPSIS
        Writes a named secret to a named vault using the active provider.

    .DESCRIPTION
        Dispatches to the provider registered by a prior Use-*Provider call.
        Creates the secret if absent; overwrites if present. Propagates all
        errors as terminating.

        The active provider is set once per session by calling one of the
        Use-*Provider registration functions (e.g.
        Use-MicrosoftPowerShellSecretStoreProvider). Calling this function
        before any provider is registered throws immediately with an
        actionable message.

        The value is never written to any output stream. Do not log or
        display the return value of callers that hold a secret.

    .PARAMETER VaultName
        Name of the vault to write to.

    .PARAMETER SecretName
        Name of the secret within the vault.

    .PARAMETER Value
        Plain-text value to store. The provider encrypts it; this function
        does not write it to any stream.

    .EXAMPLE
        Use-MicrosoftPowerShellSecretStoreProvider
        Set-InfrastructureSecret -VaultName 'MyVault' `
                                 -SecretName 'MyConfig' `
                                 -Value $json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $VaultName,

        [Parameter(Mandatory)]
        [string] $SecretName,

        [Parameter(Mandatory)]
        [string] $Value
    )

    Assert-DispatchPreconditions -VaultName $VaultName -SecretName $SecretName

    & $Script:SecretProvider.Set $VaultName $SecretName $Value
}
