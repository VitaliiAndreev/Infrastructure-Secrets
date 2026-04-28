@{
    ModuleVersion     = '2.1.0'
    GUID              = 'a3f2e1d4-7b8c-4e5f-9a0b-1c2d3e4f5a6b'
    Author            = 'Vitaly Andrev'
    Description       = 'Shared secret management for infrastructure repos: vault setup and provider-based runtime read/write.'
    PowerShellVersion = '5.1'
    RootModule        = 'Infrastructure.Secrets.psm1'
    # FunctionsToExport is module discovery metadata: used by
    # Get-Module -ListAvailable, Find-Module, and PSGallery without loading
    # the module. It does NOT control what is callable at runtime - that is
    # governed by Export-ModuleMember in the psm1, which takes precedence.
    # Both lists must stay in sync. The shared Module.Tests.ps1 in the
    # run-unit-tests action enforces this.
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
    RequiredModules   = @(
        @{
            ModuleName    = 'Infrastructure.Common'
            ModuleVersion = '1.1.0'
            GUID          = 'b7d3f2a1-4c9e-4f8d-a2b5-3e6d7f8a9b0c'
        }
    )
}
