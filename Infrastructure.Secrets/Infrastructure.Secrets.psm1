<#
.SYNOPSIS
    Shared PowerShell module for infrastructure secret vault setup.

.DESCRIPTION
    Provides Initialize-InfrastructureVault: a single function that handles all
    SecretManagement boilerplate — NuGet provider, module installation,
    SecretStore configuration, vault registration, and secret storage.

    Consuming repos call this once per machine from their own thin
    setup-secrets.ps1, passing only the project-specific vault name,
    secret name, and optional validation logic.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-InfrastructureVault {
    <#
    .SYNOPSIS
        One-time setup: installs SecretManagement modules, registers a local
        vault, and stores a JSON config string as an encrypted secret.

    .DESCRIPTION
        Idempotent — safe to re-run to update the stored config.

        The SecretStore vault is AES-256 encrypted and scoped to the current
        Windows user account. No secrets are written to disk in plain text.

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
    # 3. Ensure NuGet provider is available
    #    PowerShellGet requires NuGet >= 2.8.5.201 to install modules from
    #    PSGallery. -ForceBootstrap suppresses the interactive prompt.
    # -----------------------------------------------------------------------

    Write-Host "Ensuring NuGet package provider ..." -ForegroundColor Cyan
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 `
        -Scope CurrentUser -Force -ForceBootstrap | Out-Null
    Write-Host "✓ NuGet provider ready." -ForegroundColor Green

    # -----------------------------------------------------------------------
    # 4. Install SecretManagement modules if not already present
    #    Install all before importing any — importing SecretManagement before
    #    SecretStore is installed causes a "module in use" warning when
    #    PowerShellGet tries to satisfy SecretStore's dependency on it.
    # -----------------------------------------------------------------------

    $requiredModules = @(
        'Microsoft.PowerShell.SecretManagement',
        'Microsoft.PowerShell.SecretStore'
    )

    foreach ($mod in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Host "Installing module: $mod ..." -ForegroundColor Cyan
            Install-Module -Name $mod -Repository PSGallery `
                -Scope CurrentUser -Force
            Write-Host "✓ Installed $mod." -ForegroundColor Green
        }
        else {
            Write-Host "✓ Module already present: $mod" -ForegroundColor Green
        }
    }

    foreach ($mod in $requiredModules) {
        Import-Module $mod -ErrorAction Stop
    }

    # -----------------------------------------------------------------------
    # 5. Configure SecretStore
    #    Authentication=None means the vault is unlocked automatically for
    #    the current Windows user (key derived from Windows user profile).
    #    No separate vault password is required unless -RequireVaultPassword.
    #
    #    Detection: call Get-SecretStoreConfiguration first (official API).
    #    On an uninitialised store it throws — treat as "needs init".
    #    On a Password-auth store the cmdlet may also throw in some module
    #    versions, so we fall back to reading the storeconfig file directly.
    #
    #    Initialisation: SecretStore always requires a password on first
    #    Reset-SecretStore, even when the target auth mode is None. We
    #    supply a temp password non-interactively, then switch to the target
    #    auth mode immediately. $ConfirmPreference = 'None' suppresses the
    #    Reset-SecretStore confirmation in module versions that ignore
    #    -Confirm:$false.
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
        # version where the cmdlet throws — fall through to file fallback.
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

        $tempPass  = ConvertTo-SecureString 'InfrastructureSecretsInit1!' -AsPlainText -Force
        $savedPref = $ConfirmPreference
        try {
            $ConfirmPreference = 'None'
            Reset-SecretStore -Authentication Password -Password $tempPass `
                -Interaction None -Confirm:$false
            Set-SecretStoreConfiguration -Authentication $authMode `
                -Password $tempPass -Interaction None -Confirm:$false
        }
        finally {
            $ConfirmPreference = $savedPref
        }
        Write-Host "✓ SecretStore initialised (Authentication=$authMode)." `
            -ForegroundColor Green
    }
    else {
        Write-Host "✓ SecretStore already configured (Authentication=$authMode)." `
            -ForegroundColor Green
    }

    # -----------------------------------------------------------------------
    # 6. Register vault (idempotent)
    # -----------------------------------------------------------------------

    if (-not (Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue)) {
        Write-Host "Registering vault '$VaultName' ..." -ForegroundColor Cyan
        Register-SecretVault `
            -Name $VaultName `
            -ModuleName Microsoft.PowerShell.SecretStore `
            -DefaultVault
        Write-Host "✓ Vault '$VaultName' registered." -ForegroundColor Green
    }
    else {
        Write-Host "✓ Vault '$VaultName' already registered." -ForegroundColor Green
    }

    # -----------------------------------------------------------------------
    # 7. Store the secret (Set-Secret overwrites — safe to re-run)
    # -----------------------------------------------------------------------

    Write-Host "Storing secret '$SecretName' in vault '$VaultName' ..." `
        -ForegroundColor Cyan
    Set-Secret -Vault $VaultName -Name $SecretName -Secret $ConfigJson
    Write-Host "✓ Secret stored." -ForegroundColor Green

    # -----------------------------------------------------------------------
    # 8. Round-trip verification
    # -----------------------------------------------------------------------

    $readBack = Get-Secret -Vault $VaultName -Name $SecretName -AsPlainText
    $null = $readBack | ConvertFrom-Json   # throws if corrupted
    Write-Host "✓ Round-trip verified — '$SecretName' readable from vault." `
        -ForegroundColor Green
}

Export-ModuleMember -Function Initialize-InfrastructureVault
