<#
.SYNOPSIS
    Publishes the Infrastructure.Secrets module to the PowerShell Gallery.

.DESCRIPTION
    Local-only entry point for publishing. CI uses the reusable action in
    VitaliiAndreev/PowerShell-Common/.github/actions/publish directly -
    do not call this from workflows.

    Run from the Infrastructure-Secrets repo root after bumping
    ModuleVersion in Infrastructure.Secrets\Infrastructure.Secrets.psd1.
    Requires PowerShell-Common to be checked out as a sibling directory.
    Requires a PSGallery API key - generate one at:
        https://www.powershellgallery.com/account/apikeys

.PARAMETER ApiKey
    Your PSGallery API key.

.EXAMPLE
    .\Publish.ps1 -ApiKey 'oy2...'
#>

param(
    [Parameter(Mandatory)]
    [string] $ApiKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repo root is one level up now that this script lives under scripts\;
# PowerShell-Common is a sibling of the repo root.
$repoRoot   = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'Infrastructure.Secrets'
$version    = (Import-PowerShellDataFile `
                   (Join-Path $modulePath 'Infrastructure.Secrets.psd1')).ModuleVersion

$invokePublish = Join-Path $repoRoot `
    '..\PowerShell-Common\.github\actions\publish\Invoke-Publish.ps1'
if (-not (Test-Path $invokePublish)) {
    throw "PowerShell-Common must be checked out as a sibling of this repository."
}
. $invokePublish

Write-Host "Publishing Infrastructure.Secrets v$version to PSGallery ..."
$env:API_KEY = $ApiKey
Invoke-Publish -ModulePath $modulePath
Write-Host "Published. Install with: Install-Module Infrastructure.Secrets" `
    -ForegroundColor Green
