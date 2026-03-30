<#
.SYNOPSIS
    Publishes the Infrastructure.Secrets module to the PowerShell Gallery.

.DESCRIPTION
    Run this from the Infrastructure-Secrets repo root after bumping
    ModuleVersion in Infrastructure.Secrets\Infrastructure.Secrets.psd1.

    Requires a PSGallery API key — generate one at:
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

Write-Host "Publishing Infrastructure.Secrets v$version to PSGallery ..."
Publish-Module -Path $modulePath -NuGetApiKey $ApiKey -Repository PSGallery
Write-Host "✓ Published. Install with: Install-Module Infrastructure.Secrets" `
    -ForegroundColor Green
