BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Assert-SafeSecretIdentifier.ps1"
}

Describe 'Assert-SafeSecretIdentifier' {

    It 'passes for a valid identifier with hyphens, dots, and underscores' {
        { Assert-SafeSecretIdentifier -Value 'My-Vault.1_A' `
            -ParameterName 'VaultName' } | Should -Not -Throw
    }

    It 'throws for an empty string' {
        # PowerShell rejects empty strings for Mandatory string parameters
        # at binding time, before the regex check is reached.
        { Assert-SafeSecretIdentifier -Value '' `
            -ParameterName 'VaultName' } | Should -Throw
    }

    It 'throws for an identifier containing a semicolon' {
        { Assert-SafeSecretIdentifier -Value 'vault;drop' `
            -ParameterName 'VaultName' } |
            Should -Throw -ExpectedMessage "*VaultName*"
    }

    It 'throws for an identifier containing a dollar sign' {
        { Assert-SafeSecretIdentifier -Value '$vault' `
            -ParameterName 'SecretName' } |
            Should -Throw -ExpectedMessage "*SecretName*"
    }

    It 'throws for an identifier containing a space' {
        { Assert-SafeSecretIdentifier -Value 'my vault' `
            -ParameterName 'VaultName' } |
            Should -Throw -ExpectedMessage "*VaultName*"
    }

    It 'includes the parameter name in the error message' {
        $err = $null
        try { Assert-SafeSecretIdentifier -Value 'bad value!' `
            -ParameterName 'SecretName' }
        catch { $err = $_.Exception.Message }
        $err | Should -Match 'SecretName'
    }
}
