function Get-InfrastructureSecret {
    <#
    .SYNOPSIS
        Reads a named secret from a named vault using the active provider.

    .DESCRIPTION
        Dispatches to the provider registered by a prior Use-*Provider call.
        Propagates all errors as terminating so callers do not need to check
        return values for null.

        The active provider is set once per session by calling one of the
        Use-*Provider registration functions (e.g.
        Use-MicrosoftPowerShellSecretStoreProvider). Calling this function
        before any provider is registered throws immediately with an
        actionable message.

    .PARAMETER VaultName
        Name of the vault to read from.

    .PARAMETER SecretName
        Name of the secret within the vault.

    .EXAMPLE
        Use-MicrosoftPowerShellSecretStoreProvider
        $json = Get-InfrastructureSecret -VaultName 'MyVault' `
                                         -SecretName 'MyConfig'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $VaultName,

        [Parameter(Mandatory)]
        [string] $SecretName
    )

    Assert-DispatchPreconditions -VaultName $VaultName -SecretName $SecretName

    & $Script:SecretProvider.Get $VaultName $SecretName
}
