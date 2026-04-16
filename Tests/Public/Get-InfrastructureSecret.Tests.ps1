BeforeAll {
    $Script:SecretProvider = $null

    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-DispatchPreconditions.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Public\Get-InfrastructureSecret.ps1"
}

Describe 'Get-InfrastructureSecret' {

    BeforeEach {
        Set-Variable -Name SecretProvider -Value $null `
            -Option None -Scope Script -Force
        Mock Assert-DispatchPreconditions {}
    }

    It 'calls Assert-DispatchPreconditions with correct VaultName and SecretName' {
        $Script:SecretProvider = @{ Name = 'Test'; Get = { 'result' }; Set = {} }

        Get-InfrastructureSecret -VaultName 'MyVault' -SecretName 'MySecret'

        Should -Invoke Assert-DispatchPreconditions -Times 1 -Exactly -ParameterFilter {
            $VaultName -eq 'MyVault' -and $SecretName -eq 'MySecret'
        }
    }

    It 'returns the value from the provider .Get scriptblock' {
        $Script:SecretProvider = @{
            Name = 'Test'
            Get  = { param($v, $n) 'expected-value' }
            Set  = {}
        }

        $result = Get-InfrastructureSecret -VaultName 'Vault' -SecretName 'Secret'

        $result | Should -Be 'expected-value'
    }

    It 'dispatches .Get with correct VaultName and SecretName' {
        $script:capturedVault = $null
        $script:capturedName  = $null

        $Script:SecretProvider = @{
            Name = 'Test'
            Get  = {
                param($v, $n)
                $script:capturedVault = $v
                $script:capturedName  = $n
                'result'
            }
            Set  = {}
        }

        Get-InfrastructureSecret -VaultName 'MyVault' -SecretName 'MySecret'

        $script:capturedVault | Should -Be 'MyVault'
        $script:capturedName  | Should -Be 'MySecret'
    }
}
