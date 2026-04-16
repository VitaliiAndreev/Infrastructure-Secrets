function Initialize-MicrosoftPowerShellSecretStoreVault {
    <#
    .SYNOPSIS
        One-time setup: configures SecretStore, registers a local vault, and
        stores a JSON config string as an encrypted secret.

    .DESCRIPTION
        Idempotent - safe to re-run to update the stored config.

        Calls Use-MicrosoftPowerShellSecretStoreProvider at the start, which
        installs Microsoft.PowerShell.SecretManagement and
        Microsoft.PowerShell.SecretStore if not already present and registers
        the provider for the current session.

        The SecretStore vault is AES-256 encrypted and scoped to the current
        Windows user account via DPAPI. No secrets are written to disk in plain
        text. This function is specific to the Microsoft.PowerShell.SecretStore
        backend - for other backends, implement an equivalent
        Initialize-*Vault function that calls the corresponding Use-*Provider.

    .PARAMETER VaultName
        Name of the SecretStore vault to register (e.g. 'GHRunners').

    .PARAMETER SecretName
        Name of the secret to store inside the vault
        (e.g. 'GHRunnersConfig').

    .PARAMETER ConfigJson
        The config as a raw JSON string. Mutually exclusive with -ConfigFile.

    .PARAMETER ConfigFile
        Path to a JSON file. Contents are read and stored in the vault;
        the file itself is not modified. Mutually exclusive with -ConfigJson.

    .PARAMETER RequireVaultPassword
        When specified, the SecretStore vault requires an interactive password
        on each session. Recommended on shared or less-trusted machines.

    .PARAMETER Validate
        Optional scriptblock that receives the JSON string and performs
        project-specific validation. Throw to abort before touching the vault.

        Example:
            -Validate {
                param($json)
                $defs = @($json | ConvertFrom-Json)
                if ($defs.Count -eq 0) { throw 'No entries found.' }
            }
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory)]
        [string] $VaultName,

        [Parameter(Mandatory)]
        [string] $SecretName,

        [Parameter(Mandatory, ParameterSetName = 'Json')]
        [string] $ConfigJson,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string] $ConfigFile,

        [Parameter()]
        [switch] $RequireVaultPassword,

        [Parameter()]
        [scriptblock] $Validate
    )

    # -----------------------------------------------------------------------
    # 1. Load JSON from file or inline string
    # -----------------------------------------------------------------------

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path $ConfigFile -PathType Leaf)) {
            throw "Config file not found: $ConfigFile"
        }
        $ConfigJson = Get-Content -Raw -Path $ConfigFile
    }

    # -----------------------------------------------------------------------
    # 2. Optional project-specific validation
    #    Run before touching the vault so we fail fast on bad config.
    # -----------------------------------------------------------------------

    if ($null -ne $Validate) {
        & $Validate $ConfigJson
    }

    # -----------------------------------------------------------------------
    # 3. Ensure SecretStore modules are installed and register the provider
    #    Use-MicrosoftPowerShellSecretStoreProvider installs
    #    Microsoft.PowerShell.SecretManagement and
    #    Microsoft.PowerShell.SecretStore via Invoke-ModuleInstall, then
    #    registers the provider for the current session.
    # -----------------------------------------------------------------------

    Use-MicrosoftPowerShellSecretStoreProvider

    # -----------------------------------------------------------------------
    # 4. Configure SecretStore
    #    Authentication=None means the vault is unlocked automatically for
    #    the current Windows user (key derived from Windows user profile).
    #    No separate vault password is required unless -RequireVaultPassword.
    #
    #    Detection: call Get-SecretStoreConfiguration first (official API).
    #    On an uninitialised store it throws - treat as "needs init".
    #    On a Password-auth store the cmdlet may also throw in some module
    #    versions, so we fall back to reading the storeconfig file directly.
    #
    #    Initialisation: SecretStore always requires a password on first
    #    Reset-SecretStore, even when the target auth mode is None. We
    #    supply a temp password non-interactively, then switch to the target
    #    auth mode immediately. Reset-SecretStore has a custom confirmation
    #    check beyond ShouldProcess that requires -Force; $Global:ConfirmPreference
    #    = 'None' suppresses the remaining ShouldProcess prompt.
    # -----------------------------------------------------------------------

    $authMode = if ($RequireVaultPassword) { 'Password' } else { 'None' }

    Write-Host "Configuring SecretStore (Authentication=$authMode) ..." `
        -ForegroundColor Cyan

    $currentAuth = $null

    try {
        $storeCfg  = Get-SecretStoreConfiguration -ErrorAction Stop
        $authValue = $storeCfg.Authentication
        $currentAuth = if ($authValue -eq 0 -or "$authValue" -eq 'None') {
            'None'
        } else {
            'Password'
        }
    }
    catch {
        # Store not initialised, or Password-auth store on an older module
        # version where the cmdlet throws - fall through to file fallback.
    }

    if ($null -eq $currentAuth) {
        $storePath   = Join-Path $env:LOCALAPPDATA `
            'Microsoft\PowerShell\secretmanagement\localstore'
        $storeConfig = Join-Path $storePath 'storeconfig'

        if (Test-Path $storeConfig) {
            try {
                $fileCfg   = Get-Content $storeConfig -Raw | ConvertFrom-Json
                $authValue = $fileCfg.Authentication
                $currentAuth = if ($authValue -eq 0 -or
                                   "$authValue" -eq 'None') {
                    'None'
                } else {
                    'Password'
                }
            }
            catch { }
        }
    }

    if ($currentAuth -ne $authMode) {
        if ($null -ne $currentAuth) {
            $storePath = Join-Path $env:LOCALAPPDATA `
                'Microsoft\PowerShell\secretmanagement\localstore'
            throw (
                "SecretStore is configured with " +
                "Authentication='$currentAuth' but '$authMode' is required.`n`n" +
                "Option A - you know your vault password:`n" +
                "  Set-SecretStoreConfiguration -Authentication $authMode " +
                "-Interaction Prompt`n`n" +
                "Option B - the store has no secrets you need:`n" +
                "  Remove-Item '$storePath' -Recurse -Force`n`n" +
                "Then re-run this script."
            )
        }

        $tempPass  = ConvertTo-SecureString 'InfrastructureSecretsInit1!' `
            -AsPlainText -Force
        # $ConfirmPreference = 'None' suppresses the ShouldProcess confirmation.
        # Reset-SecretStore also has a custom confirmation check on top of
        # ShouldProcess that requires -Force to bypass.
        $savedPref = $ConfirmPreference
        try {
            $ConfirmPreference = 'None'
            Reset-SecretStore -Authentication Password -Password $tempPass `
                -Interaction None -Force
            Set-SecretStoreConfiguration -Authentication $authMode `
                -Password $tempPass -Interaction None -Confirm:$false
        }
        finally {
            $Global:ConfirmPreference = $savedPref
        }
        Write-Host "OK - SecretStore initialised (Authentication=$authMode)." `
            -ForegroundColor Green
    }
    else {
        Write-Host "OK - SecretStore already configured (Authentication=$authMode)." `
            -ForegroundColor Green
    }

    # -----------------------------------------------------------------------
    # 5. Register vault (idempotent)
    # -----------------------------------------------------------------------

    if (-not (Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue)) {
        Write-Host "Registering vault '$VaultName' ..." -ForegroundColor Cyan
        Register-SecretVault `
            -Name $VaultName `
            -ModuleName Microsoft.PowerShell.SecretStore `
            -DefaultVault
        Write-Host "OK - Vault '$VaultName' registered." -ForegroundColor Green
    }
    else {
        Write-Host "OK - Vault '$VaultName' already registered." -ForegroundColor Green
    }

    # -----------------------------------------------------------------------
    # 6. Store the secret (Set-Secret overwrites - safe to re-run)
    # -----------------------------------------------------------------------

    Write-Host "Storing secret '$SecretName' in vault '$VaultName' ..." `
        -ForegroundColor Cyan
    Set-Secret -Vault $VaultName -Name $SecretName -Secret $ConfigJson
    Write-Host "OK - Secret stored." -ForegroundColor Green

    # -----------------------------------------------------------------------
    # 7. Round-trip verification
    # -----------------------------------------------------------------------

    $readBack = Get-Secret -Vault $VaultName -Name $SecretName -AsPlainText
    $null = $readBack | ConvertFrom-Json   # throws if corrupted
    Write-Host "OK - '$SecretName' readable from vault." -ForegroundColor Green
}
