#Requires -Version 7.0
<#
.SYNOPSIS
    Runner that exposes the private Clear-AllSecrets module function to
    operators (via the menu, an Explorer launcher, or direct invocation).

.DESCRIPTION
    The actual implementation lives at
    Infrastructure.Secrets\Private\Clear-AllSecrets.ps1. It is kept
    under Private\ so a stray `Import-Module Infrastructure.Secrets`
    cannot accidentally surface a destructive utility through tab
    completion. This script dot-sources the implementation file
    directly (no Import-Module needed) and forwards its parameters.

.PARAMETER Force
    Skip the interactive `yes` confirmation. Intended for unattended
    callers; interactive operators leave it unset.

.EXAMPLE
    pwsh -NoProfile -File .\Clear-AllSecrets.ps1

    Interactive: lists every (vault, name) pair, prompts for confirmation,
    then deletes.

.EXAMPLE
    pwsh -NoProfile -File .\Clear-AllSecrets.ps1 -Force

    Unattended: deletes without prompting.
#>

[CmdletBinding()]
param(
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Implementation lives in the module's Private\ tree. Dot-source the
# file directly rather than going through Import-Module - the function
# is not exported, so Import-Module would not surface it.
$privateImpl = Join-Path $PSScriptRoot `
    '..\Infrastructure.Secrets\Private\Clear-AllSecrets.ps1'
if (-not (Test-Path -LiteralPath $privateImpl)) {
    throw "Implementation not found at: $privateImpl"
}
. $privateImpl

Clear-AllSecrets @PSBoundParameters
