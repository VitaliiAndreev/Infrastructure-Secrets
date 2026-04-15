function Use-MicrosoftPowerShellSecretStoreProvider {
    <#
    .SYNOPSIS
        Registers Microsoft.PowerShell.SecretStore as the active secret provider.

    .DESCRIPTION
        Builds a provider hashtable backed by Microsoft.PowerShell.SecretStore
        and passes it to Register-SecretProvider, which handles validation,
        ReadOnly enforcement, and idempotency.

        Microsoft.PowerShell.SecretStore is a cross-platform PowerShell module
        that stores secrets in an encrypted local file. On Windows it uses DPAPI,
        scoping the file to the current Windows user account. It is NOT the
        Windows Credential Manager.

        Call this once at the start of a session before any
        Get-InfrastructureSecret or Set-InfrastructureSecret calls.
        Re-calling with the same provider name is safe (idempotent). Calling
        with a different provider name after one is already registered throws.

        Adding a new backend requires only a new Use-*Provider function that
        calls Register-SecretProvider with its own hashtable - no other code
        changes.

    .EXAMPLE
        Use-MicrosoftPowerShellSecretStoreProvider
        $json = Get-InfrastructureSecret -VaultName 'MyVault' `
                                         -SecretName 'MyConfig'
    #>
    [CmdletBinding()]
    param()

    # Install and import the SecretManagement stack via Infrastructure.Common's
    # Invoke-ModuleInstall, which centralises the install-if-absent pattern.
    # SecretManagement is installed first because SecretStore declares it as a
    # dependency; installing SecretStore before SecretManagement is available
    # can fail on some PowerShellGet versions.
    Invoke-ModuleInstall -ModuleName 'Microsoft.PowerShell.SecretManagement'
    Invoke-ModuleInstall -ModuleName 'Microsoft.PowerShell.SecretStore'

    # $VaultName and $SecretName are passed via parameter binding, never via
    # string interpolation, so injection via identifier values is not possible.
    # $Value is passed as a named parameter to Set-Secret and never appears in
    # a command string or output stream.
    Register-SecretProvider -Provider @{
        Name = 'MicrosoftPowerShellSecretStore'
        Get  = {
            param($VaultName, $SecretName)
            Get-Secret -Vault $VaultName -Name $SecretName `
                -AsPlainText -ErrorAction Stop
        }
        Set  = {
            param($VaultName, $SecretName, $Value)
            Set-Secret -Vault $VaultName -Name $SecretName `
                -Secret $Value -ErrorAction Stop
        }
    }
}
