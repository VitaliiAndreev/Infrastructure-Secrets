@{
    ModuleVersion     = '2.0.1'
    GUID              = 'a3f2e1d4-7b8c-4e5f-9a0b-1c2d3e4f5a6b'
    Author            = 'Vitaly Andrev'
    Description       = 'Shared secret management for infrastructure repos: vault setup and provider-based runtime read/write.'
    PowerShellVersion = '5.1'
    RootModule        = 'Infrastructure.Secrets.psm1'
    FunctionsToExport = @(
        'Initialize-MicrosoftPowerShellSecretStoreVault'
        'Get-InfrastructureSecret'
        'Set-InfrastructureSecret'
        'Use-MicrosoftPowerShellSecretStoreProvider'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    # Infrastructure.Common provides Invoke-ModuleInstall, used by
    # Use-MicrosoftPowerShellSecretStoreProvider to install the SecretStore
    # stack. Declaring it here ensures it is available inside module function
    # bodies without a manual Import-Module at each call site.
    RequiredModules   = @('Infrastructure.Common')
}
