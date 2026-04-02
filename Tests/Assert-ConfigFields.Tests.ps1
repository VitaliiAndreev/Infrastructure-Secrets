BeforeAll {
    . "$PSScriptRoot\..\Infrastructure.Secrets\Public\Assert-ConfigFields.ps1"

    # Builds a PSCustomObject from a hashtable - mirrors what ConvertFrom-Json
    # produces so tests reflect real consumer usage.
    function New-TestObject([hashtable] $props) {
        [PSCustomObject] $props
    }
}

Describe 'Assert-ConfigFields' {

    Context 'when all required fields are present and non-empty' {
        It 'does not throw' {
            $obj = New-TestObject @{ vmName = 'ubuntu-01'; ipAddress = '10.0.0.1' }
            { Assert-ConfigFields -Object $obj `
                -Fields @('vmName', 'ipAddress') `
                -Context 'VM' } | Should -Not -Throw
        }

        It 'accepts numeric fields (cpuCount, memory, etc.)' {
            # Numeric values must be cast to [string] internally before
            # IsNullOrWhiteSpace - this test catches regressions on that path.
            $obj = New-TestObject @{ cpuCount = 4; vmName = 'node-01' }
            { Assert-ConfigFields -Object $obj `
                -Fields @('cpuCount', 'vmName') `
                -Context 'VM' } | Should -Not -Throw
        }
    }

    Context 'when a required field is missing' {
        It 'throws naming the missing field' {
            $obj = New-TestObject @{ vmName = 'ubuntu-01' }
            { Assert-ConfigFields -Object $obj `
                -Fields @('vmName', 'ipAddress') `
                -Context "VM 'ubuntu-01'" } |
                Should -Throw -ExpectedMessage "*missing required field 'ipAddress'*"
        }

        It 'includes the Context string in the error' {
            $obj = New-TestObject @{ vmName = 'ubuntu-01' }
            { Assert-ConfigFields -Object $obj `
                -Fields @('ipAddress') `
                -Context "VM 'ubuntu-01'" } |
                Should -Throw -ExpectedMessage "*VM 'ubuntu-01'*"
        }
    }

    Context 'when a required field is empty or whitespace' {
        It 'throws on an empty string' {
            $obj = New-TestObject @{ vmName = '' }
            { Assert-ConfigFields -Object $obj `
                -Fields @('vmName') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*empty required field 'vmName'*"
        }

        It 'throws on a whitespace-only string' {
            $obj = New-TestObject @{ vmName = '   ' }
            { Assert-ConfigFields -Object $obj `
                -Fields @('vmName') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*empty required field 'vmName'*"
        }

        It 'throws on a tab-only string' {
            $obj = New-TestObject @{ vmName = "`t" }
            { Assert-ConfigFields -Object $obj `
                -Fields @('vmName') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*empty required field 'vmName'*"
        }

        It 'throws on a null field value' {
            # ConvertFrom-Json can produce $null for omitted optional fields;
            # [string]$null coerces to "" so IsNullOrWhiteSpace catches it.
            $obj = New-TestObject @{ vmName = $null }
            { Assert-ConfigFields -Object $obj `
                -Fields @('vmName') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*empty required field 'vmName'*"
        }
    }

    Context 'when multiple fields are validated' {
        It 'reports the first failing field' {
            # Fields are checked in order - first failure wins, matching the
            # fail-fast design intent.
            $obj = New-TestObject @{ vmName = 'node-01' }
            { Assert-ConfigFields -Object $obj `
                -Fields @('missingField', 'vmName') `
                -Context 'VM' } |
                Should -Throw -ExpectedMessage "*missing required field 'missingField'*"
        }
    }
}
