BeforeAll {
    $Script:SecretProvider = $null

    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Register-SecretProvider.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Public\Use-MicrosoftPowerShellSecretStoreProvider.ps1"

    # Stubs for Infrastructure.Common and SecretManagement cmdlets not
    # installed in the test environment; mocked per-test where needed.
    function Invoke-ModuleInstall { param($ModuleName) }
    function Get-Secret { param($Vault, $Name, [switch] $AsPlainText) }
    function Set-Secret { param($Vault, $Name, $Secret) }
}

Describe 'Use-MicrosoftPowerShellSecretStoreProvider' {

    BeforeEach {
        Set-Variable -Name SecretProvider -Value $null `
            -Option None -Scope Script -Force
        Mock Invoke-ModuleInstall {}
        Mock Register-SecretProvider {}
        Mock Get-Secret { 'result' }
        Mock Set-Secret {}
    }

    It 'calls Invoke-ModuleInstall for Microsoft.PowerShell.SecretManagement' {
        Use-MicrosoftPowerShellSecretStoreProvider

        Should -Invoke Invoke-ModuleInstall -Times 1 -Exactly -ParameterFilter {
            $ModuleName -eq 'Microsoft.PowerShell.SecretManagement'
        }
    }

    It 'calls Invoke-ModuleInstall for Microsoft.PowerShell.SecretStore' {
        Use-MicrosoftPowerShellSecretStoreProvider

        Should -Invoke Invoke-ModuleInstall -Times 1 -Exactly -ParameterFilter {
            $ModuleName -eq 'Microsoft.PowerShell.SecretStore'
        }
    }

    It 'calls Register-SecretProvider with Name MicrosoftPowerShellSecretStore' {
        Use-MicrosoftPowerShellSecretStoreProvider

        Should -Invoke Register-SecretProvider -Times 1 -Exactly -ParameterFilter {
            $Provider.Name -eq 'MicrosoftPowerShellSecretStore'
        }
    }

    It 'registers a Get scriptblock that calls Get-Secret with -AsPlainText' {
        $script:capturedProvider = $null
        Mock Register-SecretProvider { $script:capturedProvider = $Provider }

        Use-MicrosoftPowerShellSecretStoreProvider

        & $script:capturedProvider.Get 'MyVault' 'MySecret'

        Should -Invoke Get-Secret -Times 1 -Exactly -ParameterFilter {
            $Vault -eq 'MyVault' -and $Name -eq 'MySecret' -and
            $AsPlainText -eq $true
        }
    }

    It 'registers a Set scriptblock that calls Set-Secret with correct arguments' {
        $script:capturedProvider = $null
        Mock Register-SecretProvider { $script:capturedProvider = $Provider }

        Use-MicrosoftPowerShellSecretStoreProvider

        & $script:capturedProvider.Set 'MyVault' 'MySecret' 'the-value'

        Should -Invoke Set-Secret -Times 1 -Exactly -ParameterFilter {
            $Vault -eq 'MyVault' -and $Name -eq 'MySecret' -and
            $Secret -eq 'the-value'
        }
    }
}
