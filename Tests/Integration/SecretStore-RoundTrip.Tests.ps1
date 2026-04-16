# ---------------------------------------------------------------------------
# Integration tests for the Set-InfrastructureSecret / Get-InfrastructureSecret
# round-trip against a real Microsoft.PowerShell.SecretStore vault.
#
# These tests run against actual SecretStore on disk and are designed to be
# safe on GitHub Actions (windows-latest) and developer machines.
#
# ISOLATION
#   A dedicated vault named below is created for each run and removed in
#   AfterAll. An existing vault with the same name is left untouched if it
#   already exists (the registration is idempotent) and is NOT removed in
#   AfterAll if it pre-existed - only vaults created by this run are cleaned up.
#
# SECRETSTORE AUTHENTICATION
#   SecretStore is initialised with Authentication=None so the tests run
#   non-interactively. If the store is already initialised with a different
#   auth mode (e.g. on a developer machine with Password auth), the tests are
#   skipped rather than resetting the store and destroying existing secrets.
# ---------------------------------------------------------------------------

BeforeAll {
    $Script:SecretProvider = $null
    $Script:VaultName      = 'InfrastructureSecretsIntegrationTest'
    $Script:SecretName     = 'RoundTripSecret'
    $Script:VaultCreated   = $false

    # Dot-source the module functions. The module is not installed in CI;
    # dot-sourcing gives us the real implementations without side effects on
    # the installed module list.
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-SafeSecretIdentifier.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-SecretProviderValid.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-DispatchPreconditions.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Register-SecretProvider.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Public\Get-InfrastructureSecret.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Public\Set-InfrastructureSecret.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Public\Use-MicrosoftPowerShellSecretStoreProvider.ps1"

    # Provide Invoke-ModuleInstall inline since Infrastructure.Common is not
    # required to be installed in the integration test environment. The real
    # implementation is tested separately in Infrastructure-Common.
    function Invoke-ModuleInstall {
        param($ModuleName)
        if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
            Install-Module $ModuleName -Scope CurrentUser -Force -SkipPublisherCheck
        }
        Import-Module $ModuleName -Force
    }

    # Install and import the SecretStore stack.
    Invoke-ModuleInstall -ModuleName 'Microsoft.PowerShell.SecretManagement'
    Invoke-ModuleInstall -ModuleName 'Microsoft.PowerShell.SecretStore'

    # ---------------------------------------------------------------------------
    # SecretStore authentication check
    #   If the store is already configured with Password auth, skip all tests
    #   rather than resetting it and destroying existing secrets.
    # ---------------------------------------------------------------------------

    $storeCfg = $null
    try { $storeCfg = Get-SecretStoreConfiguration -ErrorAction Stop } catch { }

    $authValue = if ($null -ne $storeCfg) { $storeCfg.Authentication } else { $null }
    $storeIsPassword = ($null -ne $authValue) -and
                       ($authValue -ne 0) -and ("$authValue" -ne 'None')

    if ($storeIsPassword) {
        Write-Warning (
            'SecretStore is configured with Password authentication. ' +
            'Integration tests require Authentication=None for non-interactive ' +
            'use and will be skipped to avoid resetting the store. ' +
            'To run these tests, reset the store manually: ' +
            "Reset-SecretStore -Authentication None -Interaction None"
        )
        $Script:SkipReason = 'SecretStore uses Password auth - cannot run non-interactively'
    }
    else {
        $Script:SkipReason = $null

        # Initialise the store if not yet done.
        if ($null -eq $storeCfg) {
            $tempPass      = ConvertTo-SecureString 'InfrastructureSecretsInit1!' `
                -AsPlainText -Force
            $savedPref     = $ConfirmPreference
            try {
                $ConfirmPreference = 'None'
                Reset-SecretStore -Authentication Password -Password $tempPass `
                    -Interaction None -Confirm:$false
                Set-SecretStoreConfiguration -Authentication None `
                    -Password $tempPass -Interaction None -Confirm:$false
            }
            finally { $ConfirmPreference = $savedPref }
        }

        # Register the integration test vault if it does not already exist.
        # Track whether we created it so AfterAll can clean up.
        if (-not (Get-SecretVault -Name $Script:VaultName -ErrorAction SilentlyContinue)) {
            Register-SecretVault -Name $Script:VaultName `
                -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
            $Script:VaultCreated = $true
        }

        # Register the provider for the session.
        Use-MicrosoftPowerShellSecretStoreProvider
    }
}

AfterAll {
    # Only remove the vault if this run created it, to avoid destroying a
    # pre-existing vault on a developer machine.
    if ($Script:VaultCreated) {
        Unregister-SecretVault -Name $Script:VaultName -ErrorAction SilentlyContinue
    }
}

Describe 'Set/Get-InfrastructureSecret round-trip' -Tag 'Integration' {

    It 'Get-InfrastructureSecret returns the exact value stored by Set-InfrastructureSecret' {
        # -Skip cannot reference $Script:SkipReason directly because Pester
        # evaluates -Skip during discovery, before BeforeAll runs. Use
        # Set-ItResult instead, which runs at execution time.
        if ($null -ne $Script:SkipReason) {
            Set-ItResult -Skipped -Because $Script:SkipReason
            return
        }

        $value = '{"key":"integration-test","nested":{"count":42}}'

        Set-InfrastructureSecret -VaultName $Script:VaultName `
            -SecretName $Script:SecretName -Value $value

        $result = Get-InfrastructureSecret -VaultName $Script:VaultName `
            -SecretName $Script:SecretName

        $result | Should -Be $value
    }
}
