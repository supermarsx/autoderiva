<#
.SYNOPSIS
    Scans the 'drivers' directory for folders containing driver files (.inf).

.DESCRIPTION
    This script recursively searches the 'drivers' directory for any folder that contains at least one .inf file.
    It outputs a list of relative paths to these folders to 'exports/driver_folders.txt'.
    This is useful for understanding which directories actually contain driver packages.

.EXAMPLE
    .\scripts\Get-DriverFolders.ps1
#>

$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
    Main execution function.
#>
function Main {
    # Determine the repository root (assuming script is in /scripts)
    $repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
    $driversPath = Join-Path $repoRoot "drivers"
    $outputFile = Join-Path $repoRoot "exports\driver_folders.txt"

    Write-Host "Scanning for drivers in: $driversPath" -ForegroundColor Cyan

    if (-not (Test-Path $driversPath)) {
        Write-Error "Drivers directory not found at: $driversPath"
        return
    }

    # Ensure exports directory exists
    $exportsDir = Split-Path $outputFile
    if (-not (Test-Path $exportsDir)) {
        New-Item -Path $exportsDir -ItemType Directory -Force | Out-Null
    }

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

    Write-Host "Found $( $relativePaths.Count ) driver folders." -ForegroundColor Green
    Write-Host "List saved to: $outputFile" -ForegroundColor Green
}

Main
