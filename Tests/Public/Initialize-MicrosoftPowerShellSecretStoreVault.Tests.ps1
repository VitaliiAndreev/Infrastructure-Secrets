BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Public\Initialize-MicrosoftPowerShellSecretStoreVault.ps1"

    # Stub for the provider registration call. Module install and provider
    # registration are tested in Get-InfrastructureSecret.Tests.ps1; here
    # it is mocked so vault-setup tests run without side effects.
    function Use-MicrosoftPowerShellSecretStoreProvider { }

    # Stubs for SecretManagement cmdlets not installed in the test environment.
    # Pester requires a command to exist before it can be mocked.
    function Get-SecretStoreConfiguration { }
    # $Authentication declared so Pester ParameterFilter can bind it.
    # Other parameters are intentionally omitted - they are not asserted on.
    function Set-SecretStoreConfiguration { param($Authentication) }
    function Reset-SecretStore { }
    function Get-SecretVault { }
    # Params declared so Pester ParameterFilter can bind $Name/$ModuleName/$DefaultVault.
    function Register-SecretVault { param($Name, $ModuleName, [switch]$DefaultVault) }
    # Params declared so Pester's ParameterFilter can bind $Vault/$Name/$Secret.
    function Set-Secret { param($Vault, $Name, $Secret) }
    function Get-Secret { param($Vault, $Name, [switch] $AsPlainText) }
}

Describe 'Initialize-MicrosoftPowerShellSecretStoreVault' {

    # ------------------------------------------------------------------
    # Shared mock setup for the happy path (store already configured,
    # vault already registered). Individual contexts override only what
    # they need to exercise a specific branch.
    # ------------------------------------------------------------------

    BeforeEach {
        # Suppress console output - the function is chatty by design but
        # that noise makes test output hard to read.
        Mock Write-Host {}

        # Module install and provider registration are owned by
        # Use-MicrosoftPowerShellSecretStoreProvider - stub it out here.
        Mock Use-MicrosoftPowerShellSecretStoreProvider {}

        # SecretStore already configured with Authentication=None.
        Mock Get-SecretStoreConfiguration {
            [PSCustomObject] @{ Authentication = 0 }  # 0 == None
        }

        # Vault already registered - skip Register-SecretVault.
        Mock Get-SecretVault { param($Name) return @{ Name = $Name } }
        Mock Register-SecretVault {}

        # Secret storage and round-trip verification.
        Mock Set-Secret {}
        Mock Get-Secret { '{"key":"value"}' }
        # Get-Content must be mocked in every test so Should -Invoke -Times 0
        # assertions can verify it was never called.
        Mock Get-Content {}
    }

    # ------------------------------------------------------------------
    Context 'Config loading - -ConfigFile parameter set' {
    # ------------------------------------------------------------------

        It 'throws when the config file does not exist' {
            Mock Test-Path { $false }
            { Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigFile 'C:\nonexistent.json' } |
                Should -Throw -ExpectedMessage "*Config file not found*"
        }

        It 'reads JSON from the config file' {
            Mock Test-Path { $true }
            Mock Get-Content { '{"key":"value"}' }

            Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigFile 'C:\config.json'

            Should -Invoke Get-Content -Times 1 -Exactly
        }
    }

    # ------------------------------------------------------------------
    Context 'Config loading - -ConfigJson parameter set' {
    # ------------------------------------------------------------------

        It 'accepts inline JSON without touching the filesystem' {
            Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}'

            # Test-Path and Get-Content must not be called when using -ConfigJson.
            Should -Invoke Get-Content -Times 0
        }
    }

    # ------------------------------------------------------------------
    Context 'Validation scriptblock' {
    # ------------------------------------------------------------------

        It 'calls the Validate block with the JSON string' {
            $script:capturedJson = $null
            $validate = { param($json) $script:capturedJson = $json }

            Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}' `
                -Validate $validate

            $script:capturedJson | Should -Be '{"key":"value"}'
        }

        It 'aborts before touching the vault when Validate throws' {
            $validate = { param($json) throw 'Invalid config' }

            { Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}' `
                -Validate $validate } |
                Should -Throw -ExpectedMessage "*Invalid config*"

            # The vault must not be touched if validation failed.
            Should -Invoke Set-Secret -Times 0
        }
    }

    # ------------------------------------------------------------------
    Context 'Provider registration' {
    # ------------------------------------------------------------------

        It 'calls Use-MicrosoftPowerShellSecretStoreProvider before touching the vault' {
            Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}'

            Should -Invoke Use-MicrosoftPowerShellSecretStoreProvider -Times 1 -Exactly
        }
    }

    # ------------------------------------------------------------------
    Context 'SecretStore configuration - auth mode mismatch' {
    # ------------------------------------------------------------------

        It 'throws a helpful message when the store uses Password but None is required' {
            Mock Get-SecretStoreConfiguration {
                [PSCustomObject] @{ Authentication = 1 }  # 1 == Password
            }

            { Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}' } |
                Should -Throw -ExpectedMessage "*Authentication='Password'*"
        }

        It 'throws a helpful message when the store uses None but Password is required' {
            # Default mock returns Authentication=None; flag demands Password.
            { Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}' `
                -RequireVaultPassword } |
                Should -Throw -ExpectedMessage "*Authentication='None'*"
        }

        It 'error message includes remediation options A and B' {
            Mock Get-SecretStoreConfiguration {
                [PSCustomObject] @{ Authentication = 1 }
            }

            $err = $null
            try {
                Initialize-MicrosoftPowerShellSecretStoreVault `
                    -VaultName 'TestVault' -SecretName 'TestSecret' `
                    -ConfigJson '{"key":"value"}'
            }
            catch { $err = $_.Exception.Message }

            $err | Should -Match 'Option A'
            $err | Should -Match 'Option B'
        }
    }

    # ------------------------------------------------------------------
    Context 'SecretStore configuration - uninitialised store' {
    # ------------------------------------------------------------------

        It 'initialises the store when Get-SecretStoreConfiguration throws and no storeconfig file exists' {
            Mock Get-SecretStoreConfiguration { throw 'not initialised' }
            Mock Test-Path { $false }   # storeconfig file absent
            Mock Reset-SecretStore {}
            Mock Set-SecretStoreConfiguration {}

            Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}'

            Should -Invoke Reset-SecretStore -Times 1 -Exactly
            Should -Invoke Set-SecretStoreConfiguration -Times 1 -Exactly
        }

        It 'uses storeconfig file fallback when Get-SecretStoreConfiguration throws but file exists with matching auth' {
            # Older module versions throw on a Password-auth store; the file
            # fallback reads auth mode directly so the mismatch check still works.
            Mock Get-SecretStoreConfiguration { throw 'cmdlet unavailable' }
            Mock Test-Path { $true }   # storeconfig file present
            Mock Get-Content { '{"Authentication":0}' }  # 0 == None, matches default $authMode
            Mock Reset-SecretStore {}
            Mock Set-SecretStoreConfiguration {}

            Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}'

            # Auth matched via file - no store reset should have occurred.
            Should -Invoke Reset-SecretStore -Times 0
        }

        It 'initialises the store with Authentication Password when -RequireVaultPassword and store is uninitialised' {
            Mock Get-SecretStoreConfiguration { throw 'not initialised' }
            Mock Test-Path { $false }
            Mock Reset-SecretStore {}
            Mock Set-SecretStoreConfiguration {}

            Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}' `
                -RequireVaultPassword

            Should -Invoke Reset-SecretStore -Times 1 -Exactly
            Should -Invoke Set-SecretStoreConfiguration -Times 1 -Exactly -ParameterFilter {
                $Authentication -eq 'Password'
            }
        }

        It 'throws a mismatch error when storeconfig file shows Password but None is required' {
            Mock Get-SecretStoreConfiguration { throw 'cmdlet unavailable' }
            Mock Test-Path { $true }
            Mock Get-Content { '{"Authentication":1}' }  # 1 == Password, but None required
            Mock Reset-SecretStore {}
            Mock Set-SecretStoreConfiguration {}

            { Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}' } |
                Should -Throw -ExpectedMessage "*Authentication='Password'*"
        }
    }

    # ------------------------------------------------------------------
    Context 'SecretStore configuration - RequireVaultPassword happy path' {
    # ------------------------------------------------------------------

        It 'succeeds when store is already configured with Password auth and -RequireVaultPassword is set' {
            Mock Get-SecretStoreConfiguration {
                [PSCustomObject] @{ Authentication = 1 }  # 1 == Password
            }

            { Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}' `
                -RequireVaultPassword } | Should -Not -Throw

            Should -Invoke Set-Secret -Times 1 -Exactly
        }
    }

    # ------------------------------------------------------------------
    Context 'Vault registration' {
    # ------------------------------------------------------------------

        It 'registers the vault when it does not yet exist' {
            Mock Get-SecretVault { $null }

            Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}'

            Should -Invoke Register-SecretVault -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'TestVault' -and
                $ModuleName -eq 'Microsoft.PowerShell.SecretStore' -and
                $DefaultVault -eq $true
            }
        }

        It 'skips registration when the vault is already registered' {
            # Default BeforeEach mock: Get-SecretVault returns an object.
            Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}'

            Should -Invoke Register-SecretVault -Times 0
        }
    }

    # ------------------------------------------------------------------
    Context 'Secret storage and verification' {
    # ------------------------------------------------------------------

        It 'stores the secret in the named vault' {
            Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'MyVault' -SecretName 'MySecret' `
                -ConfigJson '{"key":"value"}'

            Should -Invoke Set-Secret -Times 1 -Exactly -ParameterFilter {
                $Vault -eq 'MyVault' -and $Name -eq 'MySecret' -and
                $Secret -eq '{"key":"value"}'
            }
        }

        It 'throws when the round-trip read returns invalid JSON' {
            Mock Get-Secret { 'not-valid-json{{{{' }

            { Initialize-MicrosoftPowerShellSecretStoreVault `
                -VaultName 'TestVault' -SecretName 'TestSecret' `
                -ConfigJson '{"key":"value"}' } |
                Should -Throw
        }
    }
}
