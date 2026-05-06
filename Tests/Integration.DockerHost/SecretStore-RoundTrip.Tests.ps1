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

    # Install and import the SecretStore stack once. Modules are not installed
    # again later - Register-SecretProvider is called directly below to avoid
    # a second Import-Module that can interfere with the store configuration
    # that was just applied.
    foreach ($mod in @('Microsoft.PowerShell.SecretManagement',
                       'Microsoft.PowerShell.SecretStore')) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Install-Module $mod -Scope CurrentUser -Force -SkipPublisherCheck
        }
        Import-Module $mod -Force
    }

    # ---------------------------------------------------------------------------
    # SecretStore authentication check
    #   If the store is already configured with Password auth, skip all tests
    #   rather than resetting it and destroying existing secrets.
    # ---------------------------------------------------------------------------

    # Detect initialisation via the store directory rather than calling
    # Get-SecretStoreConfiguration. On an uninitialised store that cmdlet does
    # not throw - it prompts for a password interactively, and $ConfirmPreference
    # does not suppress that kind of input request. Checking the directory is the
    # only way to branch without triggering the prompt.
    $isWin    = $env:OS -eq 'Windows_NT'   # $IsWindows requires PS 6+
    $storeDir = if ($isWin) {
        [IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft', 'PowerShell',
            'secretmanagement', 'localstore')
    } else {
        [IO.Path]::Combine($HOME, '.secretmanagement', 'localstore')
    }
    $storeInitialised = Test-Path $storeDir

    # $ConfirmPreference = 'None' suppresses the ShouldProcess confirmation.
    # Reset-SecretStore also has a custom confirmation check on top of
    # ShouldProcess that requires -Force to bypass.
    $savedPref = $ConfirmPreference
    $ConfirmPreference = 'None'

    if (-not $storeInitialised) {
        # Fresh environment - initialise directly with Authentication=None.
        $Script:SkipReason = $null
        $tempPass = ConvertTo-SecureString 'InfrastructureSecretsInit1!' `
            -AsPlainText -Force
        Reset-SecretStore -Authentication Password -Password $tempPass `
            -Interaction None -Force
        Set-SecretStoreConfiguration -Authentication None `
            -Password $tempPass -Interaction None -Confirm:$false
    }
    else {
        # Store exists - safe to read its configuration now.
        $storeCfg = $null
        try { $storeCfg = Get-SecretStoreConfiguration -ErrorAction Stop } catch { }

        $authValue       = if ($null -ne $storeCfg) { $storeCfg.Authentication } else { $null }
        $storeIsPassword = ($null -ne $authValue) -and
                           ($authValue -ne 0) -and ("$authValue" -ne 'None')

        if ($storeIsPassword) {
            $ConfirmPreference = $savedPref
            Write-Warning (
                'SecretStore is configured with Password authentication. ' +
                'Integration tests require Authentication=None for non-interactive ' +
                'use and will be skipped to avoid resetting the store.'
            )
            $Script:SkipReason = 'SecretStore uses Password auth - cannot run non-interactively'
        }
        else {
            $Script:SkipReason = $null
        }
    }

    $ConfirmPreference = $savedPref

    if ($null -eq $Script:SkipReason) {

        # Register the integration test vault if it does not already exist.
        # Track whether we created it so AfterAll can clean up.
        if (-not (Get-SecretVault -Name $Script:VaultName -ErrorAction SilentlyContinue)) {
            Register-SecretVault -Name $Script:VaultName `
                -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
            $Script:VaultCreated = $true
        }

        # Register the provider directly. Use-MicrosoftPowerShellSecretStoreProvider
        # is intentionally not called here - it would re-import the already-loaded
        # SecretStore modules, which can interfere with the auth configuration
        # applied above. The provider scriptblocks are identical to what
        # Use-MicrosoftPowerShellSecretStoreProvider registers.
        Register-SecretProvider -Provider @{
            Name = 'MicrosoftPowerShellSecretStore'
            Get  = { param($VaultName, $SecretName)
                     Get-Secret -Vault $VaultName -Name $SecretName `
                         -AsPlainText -ErrorAction Stop }
            Set  = { param($VaultName, $SecretName, $Value)
                     Set-Secret -Vault $VaultName -Name $SecretName `
                         -Secret $Value -ErrorAction Stop }
        }
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
