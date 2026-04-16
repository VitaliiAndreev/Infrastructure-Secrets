BeforeAll {
    $Script:SecretProvider = $null

    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-SafeSecretIdentifier.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-SecretProviderValid.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-DispatchPreconditions.ps1"
}

Describe 'Assert-DispatchPreconditions' {

    BeforeEach {
        Set-Variable -Name SecretProvider -Value $null `
            -Option None -Scope Script -Force
        Mock Assert-SafeSecretIdentifier {}
        Mock Assert-SecretProviderValid {}
    }

    It 'calls Assert-SafeSecretIdentifier for VaultName with correct arguments' {
        Assert-DispatchPreconditions -VaultName 'MyVault' -SecretName 'MySecret'

        Should -Invoke Assert-SafeSecretIdentifier -Times 1 -Exactly -ParameterFilter {
            $Value -eq 'MyVault' -and $ParameterName -eq 'VaultName'
        }
    }

    It 'calls Assert-SafeSecretIdentifier for SecretName with correct arguments' {
        Assert-DispatchPreconditions -VaultName 'MyVault' -SecretName 'MySecret'

        Should -Invoke Assert-SafeSecretIdentifier -Times 1 -Exactly -ParameterFilter {
            $Value -eq 'MySecret' -and $ParameterName -eq 'SecretName'
        }
    }

    It 'calls Assert-SecretProviderValid with the module provider' {
        $provider = @{ Name = 'Test'; Get = {}; Set = {} }
        $Script:SecretProvider = $provider

        Assert-DispatchPreconditions -VaultName 'Vault' -SecretName 'Secret'

        Should -Invoke Assert-SecretProviderValid -Times 1 -Exactly -ParameterFilter {
            $Provider -eq $provider
        }
    }
}
