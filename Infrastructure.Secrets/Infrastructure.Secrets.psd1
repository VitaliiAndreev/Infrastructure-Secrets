@{
    ModuleVersion     = '2.0.1'
    GUID              = 'a3f2e1d4-7b8c-4e5f-9a0b-1c2d3e4f5a6b'
    Author            = 'Vitaly Andrev'
    Description       = 'Shared SecretManagement vault setup for infrastructure repos.'
    PowerShellVersion = '5.1'
    RootModule        = 'Infrastructure.Secrets.psm1'
    FunctionsToExport = @('Initialize-InfrastructureVault')
    CmdletsToExport   = @()
    AliasesToExport   = @()
    RequiredModules   = @()
}
