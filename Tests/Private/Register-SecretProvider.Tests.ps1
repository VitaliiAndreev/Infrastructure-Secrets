BeforeAll {
    $Script:SecretProvider = $null

    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-SecretProviderValid.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Register-SecretProvider.ps1"
}

Describe 'Register-SecretProvider' {

    BeforeEach {
        Set-Variable -Name SecretProvider -Value $null `
            -Option None -Scope Script -Force
        Mock Assert-SecretProviderValid {}
    }

    It 'calls Assert-SecretProviderValid with the provider' {
        $provider = @{ Name = 'TestProvider'; Get = {}; Set = {} }
        Register-SecretProvider -Provider $provider
        Should -Invoke Assert-SecretProviderValid -Times 1 -Exactly -ParameterFilter {
            $Provider -eq $provider
        }
    }

    It 'succeeds on first registration and marks the variable ReadOnly' {
        Register-SecretProvider -Provider @{
            Name = 'TestProvider'; Get = {}; Set = {}
        }
        # A plain assignment must fail because the variable is ReadOnly.
        { $Script:SecretProvider = $null } | Should -Throw
    }

    It 're-registering the same provider name is idempotent' {
        Register-SecretProvider -Provider @{
            Name = 'TestProvider'; Get = {}; Set = {}
        }
        { Register-SecretProvider -Provider @{
            Name = 'TestProvider'; Get = {}; Set = {}
        } } | Should -Not -Throw
    }

    It 're-registering the same provider name updates the stored scriptblocks' {
        Register-SecretProvider -Provider @{
            Name = 'TestProvider'
            Get  = { 'original' }
            Set  = {}
        }

        $newGet = { 'updated' }
        Register-SecretProvider -Provider @{
            Name = 'TestProvider'
            Get  = $newGet
            Set  = {}
        }

        # The stored provider must reflect the new scriptblock, not the old one.
        $Script:SecretProvider.Get | Should -Be $newGet
    }

    It 'throws when a different provider name is already registered' {
        Register-SecretProvider -Provider @{
            Name = 'ProviderA'; Get = {}; Set = {}
        }
        { Register-SecretProvider -Provider @{
            Name = 'ProviderB'; Get = {}; Set = {}
        } } | Should -Throw -ExpectedMessage "*Import-Module*"
    }

    It 'direct assignment throws after registration' {
        Register-SecretProvider -Provider @{
            Name = 'TestProvider'; Get = {}; Set = {}
        }
        { $Script:SecretProvider = @{ Name = 'X'; Get = {}; Set = {} } } |
            Should -Throw
    }
}
