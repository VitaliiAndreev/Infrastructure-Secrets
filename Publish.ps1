<#
.SYNOPSIS
    Publishes the Infrastructure.Secrets module to the PowerShell Gallery.

.DESCRIPTION
    Local-only entry point for publishing. CI uses the reusable action in
    VitaliiAndreev/Infrastructure-Common/.github/actions/publish directly -
    do not call this from workflows.

    Run from the Infrastructure-Secrets repo root after bumping
    ModuleVersion in Infrastructure.Secrets\Infrastructure.Secrets.psd1.
    Requires Infrastructure-Common to be checked out as a sibling directory.
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

$modulePath = Join-Path $PSScriptRoot 'Infrastructure.Secrets'
$version    = (Import-PowerShellDataFile `
                   (Join-Path $modulePath 'Infrastructure.Secrets.psd1')).ModuleVersion

$invokePublish = Join-Path $PSScriptRoot `
    '..\Infrastructure-Common\.github\actions\publish\Invoke-Publish.ps1'
if (-not (Test-Path $invokePublish)) {
    throw "Infrastructure-Common must be checked out as a sibling of this repository."
}
. $invokePublish

Write-Host "Publishing Infrastructure.Secrets v$version to PSGallery ..."
$env:API_KEY = $ApiKey
Invoke-Publish -ModulePath $modulePath
Write-Host "Published. Install with: Install-Module Infrastructure.Secrets" `
    -ForegroundColor Green
