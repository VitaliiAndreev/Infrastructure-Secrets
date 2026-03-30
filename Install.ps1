<#
.SYNOPSIS
    Installs Infrastructure.Secrets locally from source for development use.

.DESCRIPTION
    For development and testing of the module itself only.
    Consuming repos install from PSGallery — they do not call this script.

    Idempotent — skips installation if the module is already up to date.

.EXAMPLE
    .\Install.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleSrc   = Join-Path $PSScriptRoot 'Infrastructure.Secrets'
$moduleDst   = Join-Path ([Environment]::GetFolderPath('MyDocuments')) `
                   'WindowsPowerShell\Modules\Infrastructure.Secrets'

$srcVersion  = (Import-PowerShellDataFile `
                    (Join-Path $moduleSrc 'Infrastructure.Secrets.psd1')).ModuleVersion
$dstManifest = Join-Path $moduleDst 'Infrastructure.Secrets.psd1'
$dstVersion  = if (Test-Path $dstManifest) {
                   (Import-PowerShellDataFile $dstManifest).ModuleVersion
               } else { $null }

if ($srcVersion -eq $dstVersion) {
    Write-Host "✓ Infrastructure.Secrets v$srcVersion already installed - skipping." `
        -ForegroundColor Green
    return
}

Write-Host "Installing Infrastructure.Secrets v$srcVersion from source ..."
if (Test-Path $moduleDst) { Remove-Item $moduleDst -Recurse -Force }
Copy-Item -Path $moduleSrc -Destination $moduleDst -Recurse
Write-Host "✓ Infrastructure.Secrets v$srcVersion installed." -ForegroundColor Green
