$ErrorActionPreference = "Stop"

# Determine the repository root (assuming script is in /scripts)
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$driversPath = Join-Path $repoRoot "drivers"
$outputFile = Join-Path $repoRoot "driver_folders.txt"

Write-Host "Scanning for drivers in: $driversPath"

# Find all folders containing .inf files
$driverFolders = Get-ChildItem -Path $driversPath -Recurse -Filter "*.inf" | 
Select-Object -ExpandProperty DirectoryName | 
Sort-Object -Unique

# Convert to relative paths
$relativePaths = $driverFolders | ForEach-Object {
    # Get path relative to repo root
    $_.Substring($repoRoot.Length + 1)
}

# Output to file
$relativePaths | Out-File -FilePath $outputFile -Encoding utf8

Write-Host "Found $( $relativePaths.Count ) driver folders."
Write-Host "List saved to: $outputFile"
