BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-SecretProviderValid.ps1"
}

Describe 'Assert-SecretProviderValid' {

    It 'throws when provider is null' {
        { Assert-SecretProviderValid -Provider $null } |
            Should -Throw -ExpectedMessage "*null*"
    }

    It 'throws when provider is not a hashtable' {
        { Assert-SecretProviderValid -Provider 'a string' } |
            Should -Throw -ExpectedMessage "*hashtable*"
    }

    It 'throws when Name key is missing' {
        { Assert-SecretProviderValid -Provider @{ Get = {}; Set = {} } } |
            Should -Throw -ExpectedMessage "*Name*"
    }

    It 'throws when Name is blank' {
        { Assert-SecretProviderValid `
            -Provider @{ Name = '   '; Get = {}; Set = {} } } |
            Should -Throw -ExpectedMessage "*Name*"
    }

    It 'throws when Get key is missing' {
        { Assert-SecretProviderValid `
            -Provider @{ Name = 'P'; Set = {} } } |
            Should -Throw -ExpectedMessage "*Get*"
    }

    It 'throws when Set key is missing' {
        { Assert-SecretProviderValid `
            -Provider @{ Name = 'P'; Get = {} } } |
            Should -Throw -ExpectedMessage "*Set*"
    }

    It 'throws when Get is not a ScriptBlock' {
        { Assert-SecretProviderValid `
            -Provider @{ Name = 'P'; Get = 'notablock'; Set = {} } } |
            Should -Throw -ExpectedMessage "*Get*ScriptBlock*"
    }

    It 'throws when Set is not a ScriptBlock' {
        { Assert-SecretProviderValid `
            -Provider @{ Name = 'P'; Get = {}; Set = 'notablock' } } |
            Should -Throw -ExpectedMessage "*Set*ScriptBlock*"
    }

    It 'passes for a well-formed provider' {
        { Assert-SecretProviderValid `
            -Provider @{ Name = 'P'; Get = {}; Set = {} } } |
            Should -Not -Throw
    }
}
