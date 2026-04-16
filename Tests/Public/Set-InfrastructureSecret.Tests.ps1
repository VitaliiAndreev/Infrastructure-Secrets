BeforeAll {
    $Script:SecretProvider = $null

    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-DispatchPreconditions.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Public\Set-InfrastructureSecret.ps1"
}

Describe 'Set-InfrastructureSecret' {

    BeforeEach {
        Set-Variable -Name SecretProvider -Value $null `
            -Option None -Scope Script -Force
        Mock Assert-DispatchPreconditions {}
    }

    It 'calls Assert-DispatchPreconditions with correct VaultName and SecretName' {
        $Script:SecretProvider = @{ Name = 'Test'; Get = {}; Set = {} }

        Set-InfrastructureSecret -VaultName 'MyVault' `
            -SecretName 'MySecret' -Value 'val'

        Should -Invoke Assert-DispatchPreconditions -Times 1 -Exactly -ParameterFilter {
            $VaultName -eq 'MyVault' -and $SecretName -eq 'MySecret'
        }
    }

    It 'dispatches .Set with correct VaultName, SecretName, and Value' {
        $script:capturedVault = $null
        $script:capturedName  = $null
        $script:capturedValue = $null

        $Script:SecretProvider = @{
            Name = 'Test'
            Get  = {}
            Set  = {
                param($v, $n, $val)
                $script:capturedVault = $v
                $script:capturedName  = $n
                $script:capturedValue = $val
            }
        }

        Set-InfrastructureSecret -VaultName 'MyVault' `
            -SecretName 'MySecret' -Value 'my-value'

        $script:capturedVault | Should -Be 'MyVault'
        $script:capturedName  | Should -Be 'MySecret'
        $script:capturedValue | Should -Be 'my-value'
    }

    It 'passes Value containing special characters without validation' {
        $script:capturedValue = $null

        $Script:SecretProvider = @{
            Name = 'Test'
            Get  = {}
            Set  = { param($v, $n, $val) $script:capturedValue = $val }
        }

        Set-InfrastructureSecret -VaultName 'Vault' -SecretName 'Secret' `
            -Value '{"key":"val;$ue & more"}'

        $script:capturedValue | Should -Be '{"key":"val;$ue & more"}'
    }
}
