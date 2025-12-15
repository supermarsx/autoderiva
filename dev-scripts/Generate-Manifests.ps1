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

# Validation: report inventory entries missing InfPath and manifest entries referencing missing INFs
$invFile = Join-Path $repoRoot 'exports\driver_inventory.csv'
$manifestFile = Join-Path $repoRoot 'exports\driver_file_manifest.csv'
if ((Test-Path $invFile) -and (Test-Path $manifestFile)) {
    $inv = Import-Csv -Path $invFile
    $manifest = Import-Csv -Path $manifestFile

    $missingInf = $inv | Where-Object { -not $_.InfPath -or [string]::IsNullOrWhiteSpace($_.InfPath) }
    if ($missingInf.Count -gt 0) {
        Write-Host "WARNING: Found $($missingInf.Count) inventory entries missing InfPath. See below sample:" -ForegroundColor Yellow
        $missingInf | Select-Object -First 10 | Format-Table FileName, HardwareIDs | Out-Host
    } else {
        Write-Host "Inventory: all entries include InfPath." -ForegroundColor Green
    }

    # Manifest references check (split multi-valued AssociatedInf entries)
    $invInfPaths = $inv | Where-Object { $_.InfPath } | ForEach-Object { ($_.InfPath.Replace('\','/')).ToLower() }
    $badRefs = @()
    foreach ($m in $manifest) {
        if (-not $m.AssociatedInf) { continue }
        $parts = $m.AssociatedInf -split ';' | ForEach-Object { $_.Trim().Replace('\','/').ToLower() } | Where-Object { $_ }
        $resolved = $parts | Where-Object { $invInfPaths -contains $_ }
        if (-not $resolved -or $resolved.Count -eq 0) { $badRefs += $m }
    }
    if ($badRefs.Count -gt 0) {
        Write-Host "WARNING: Found $($badRefs.Count) manifest entries referencing INFs that are not present in the inventory." -ForegroundColor Yellow
        $badRefs | Select-Object -First 10 | Format-Table FileName, RelativePath, AssociatedInf | Out-Host
    } else {
        Write-Host "Manifest: all AssociatedInf references resolved against inventory." -ForegroundColor Green
    }
}
