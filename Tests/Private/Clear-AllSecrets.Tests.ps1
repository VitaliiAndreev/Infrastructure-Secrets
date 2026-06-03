BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.Secrets\Private\Clear-AllSecrets.ps1"

    # Stubs for SecretManagement cmdlets not installed in the test
    # environment. Pester requires a command to exist before it can be
    # mocked. Param blocks are declared so ParameterFilter can bind them.
    function Get-SecretVault { }
    function Get-SecretInfo { param($Vault) }
    function Remove-Secret { param($Vault, $Name) }
}

Describe 'Clear-AllSecrets' {

    BeforeEach {
        # Suppress the function's chatty progress output - the noise
        # makes test failures hard to read.
        Mock Write-Host {}
        # Out-Host is invoked through the pipeline for the victim table;
        # mock it so the table does not render during the test run.
        Mock Out-Host {}
    }

    # ------------------------------------------------------------------
    Context 'No vaults registered' {
    # ------------------------------------------------------------------

        It 'returns early without prompting or deleting' {
            Mock Get-SecretVault { $null }
            Mock Get-SecretInfo {}
            Mock Read-Host {}
            Mock Remove-Secret {}

            Clear-AllSecrets

            Should -Invoke Read-Host    -Times 0 -Exactly
            Should -Invoke Remove-Secret -Times 0 -Exactly
        }
    }

    # ------------------------------------------------------------------
    Context 'Vaults exist but are empty' {
    # ------------------------------------------------------------------

        It 'returns early without prompting or deleting' {
            Mock Get-SecretVault { @([PSCustomObject]@{ Name = 'V1' }) }
            Mock Get-SecretInfo  { @() }
            Mock Read-Host {}
            Mock Remove-Secret {}

            Clear-AllSecrets

            Should -Invoke Read-Host    -Times 0 -Exactly
            Should -Invoke Remove-Secret -Times 0 -Exactly
        }
    }

    # ------------------------------------------------------------------
    Context 'Interactive confirmation' {
    # ------------------------------------------------------------------

        BeforeEach {
            Mock Get-SecretVault {
                @([PSCustomObject]@{ Name = 'V1' })
            }
            Mock Get-SecretInfo {
                @([PSCustomObject]@{ Name = 's1' },
                  [PSCustomObject]@{ Name = 's2' })
            }
            Mock Remove-Secret {}
        }

        It 'aborts when the operator types anything other than "yes"' {
            Mock Read-Host { 'no' }

            Clear-AllSecrets

            Should -Invoke Remove-Secret -Times 0 -Exactly
        }

        It 'aborts on empty input' {
            Mock Read-Host { '' }

            Clear-AllSecrets

            Should -Invoke Remove-Secret -Times 0 -Exactly
        }

        It 'accepts "YES" - the -ne comparison is case-insensitive' {
            # PowerShell's -ne is case-insensitive by default, so the
            # prompt's literal `yes` instruction is a hint, not a hard
            # rule. Pin the behaviour so a future switch to -cne (or a
            # rewrite using string.Equals) does not silently regress.
            Mock Read-Host { 'YES' }

            Clear-AllSecrets

            Should -Invoke Remove-Secret -Times 2 -Exactly
        }

        It 'deletes every (vault, name) pair when the operator confirms' {
            Mock Read-Host { 'yes' }

            Clear-AllSecrets

            Should -Invoke Remove-Secret -Times 2 -Exactly
            Should -Invoke Remove-Secret -Times 1 -Exactly -ParameterFilter {
                $Vault -eq 'V1' -and $Name -eq 's1'
            }
            Should -Invoke Remove-Secret -Times 1 -Exactly -ParameterFilter {
                $Vault -eq 'V1' -and $Name -eq 's2'
            }
        }
    }

    # ------------------------------------------------------------------
    Context '-Force bypasses confirmation' {
    # ------------------------------------------------------------------

        It 'never calls Read-Host and deletes immediately' {
            Mock Get-SecretVault {
                @([PSCustomObject]@{ Name = 'V1' })
            }
            Mock Get-SecretInfo {
                @([PSCustomObject]@{ Name = 's1' })
            }
            Mock Read-Host    { throw 'Read-Host must not be called under -Force' }
            Mock Remove-Secret {}

            Clear-AllSecrets -Force

            Should -Invoke Read-Host    -Times 0 -Exactly
            Should -Invoke Remove-Secret -Times 1 -Exactly
        }
    }

    # ------------------------------------------------------------------
    Context 'Shared-store "not found" path' {
    # ------------------------------------------------------------------

        # The same underlying SecretStore file can be reached through
        # multiple registered vault names. Removing through the first
        # vault makes the second attempt report "not found"; that branch
        # must be treated as a benign skip, not a failure.

        It 'treats "not found" as a benign skip, not a failure' {
            Mock Get-SecretVault {
                @([PSCustomObject]@{ Name = 'V1' },
                  [PSCustomObject]@{ Name = 'V2' })
            }
            Mock Get-SecretInfo {
                @([PSCustomObject]@{ Name = 'shared' })
            }
            # First call (V1) succeeds, second (V2) raises "not found".
            $script:callCount = 0
            Mock Remove-Secret {
                $script:callCount++
                if ($script:callCount -eq 2) {
                    throw [System.Exception]::new('Secret shared was not found')
                }
            }

            Clear-AllSecrets -Force

            # Both attempts happen - the "not found" branch must not
            # short-circuit the loop.
            Should -Invoke Remove-Secret -Times 2 -Exactly
            # And the function must not surface anything in red. The
            # exact output is not asserted (covered by manual review);
            # the contract here is that the function runs to completion
            # without re-throwing.
        }
    }

    # ------------------------------------------------------------------
    Context 'Genuine deletion failures' {
    # ------------------------------------------------------------------

        It 'continues past a failure and processes the remaining secrets' {
            Mock Get-SecretVault {
                @([PSCustomObject]@{ Name = 'V1' })
            }
            Mock Get-SecretInfo {
                @([PSCustomObject]@{ Name = 'a' },
                  [PSCustomObject]@{ Name = 'b' },
                  [PSCustomObject]@{ Name = 'c' })
            }
            # Middle secret raises a non-"not found" error - the loop
            # must record it and keep going rather than abort.
            Mock Remove-Secret {
                param($Vault, $Name)
                if ($Name -eq 'b') {
                    throw [System.Exception]::new('vault is locked')
                }
            }

            Clear-AllSecrets -Force

            Should -Invoke Remove-Secret -Times 3 -Exactly
        }
    }
}
