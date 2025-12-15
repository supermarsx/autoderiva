<#
.SYNOPSIS
    Regenerate the driver inventory and file manifest exported CSVs.
#>

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
Write-Host "Regenerating driver inventory and file manifest in: $repoRoot" -ForegroundColor Cyan

# Run inventory
& "$repoRoot\scripts\Get-DriverInventory.ps1"

# Run file manifest
& "$repoRoot\scripts\Get-DriverFileManifest.ps1"

Write-Host "Regeneration complete." -ForegroundColor Green
