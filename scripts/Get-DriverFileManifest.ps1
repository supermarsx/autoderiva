$ErrorActionPreference = "Stop"

# Get-DriverFileManifest.ps1
# Generates a complete list of all files in the 'drivers' directory with relative paths and sizes.
# This allows remote scripts to reconstruct driver packages by downloading individual files.

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$driversPath = Join-Path $repoRoot "drivers"
$outputFile = Join-Path $repoRoot "exports\driver_file_manifest.csv"

Write-Host "Scanning for all files in: $driversPath"

if (-not (Test-Path $driversPath)) {
    Write-Error "Drivers directory not found!"
}

$files = Get-ChildItem -Path $driversPath -Recurse -File

$results = $files | ForEach-Object {
    # Calculate relative path (e.g., drivers/gw1-w149/...)
    # We use forward slashes '/' to ensure compatibility with URL structures
    $relPath = $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
    
    [PSCustomObject]@{
        RelativePath = $relPath
        Size         = $_.Length
    }
}

$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding utf8

Write-Host "Manifest complete. Found $( $results.Count ) files."
Write-Host "Saved to: $outputFile"
