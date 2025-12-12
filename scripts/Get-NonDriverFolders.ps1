<#
.SYNOPSIS
    Scans the 'drivers' directory for folders that do NOT contain driver files (.inf).

.DESCRIPTION
    This script recursively searches the 'drivers' directory for folders that contain files but NO .inf files.
    It outputs a list of relative paths to these folders to 'exports/non_driver_folders.txt'.
    This helps identify folders that might contain documentation, utilities, or other non-driver assets.

.EXAMPLE
    .\scripts\Get-NonDriverFolders.ps1
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
    $outputFile = Join-Path $repoRoot "exports\non_driver_folders.txt"

    Write-Host "Scanning for non-driver folders in: $driversPath" -ForegroundColor Cyan

    if (-not (Test-Path $driversPath)) {
        Write-Error "Drivers directory not found at: $driversPath"
        return
    }

    # Ensure exports directory exists
    $exportsDir = Split-Path $outputFile
    if (-not (Test-Path $exportsDir)) {
        New-Item -Path $exportsDir -ItemType Directory -Force | Out-Null
    }

    # Get all directories
    $allFolders = Get-ChildItem -Path $driversPath -Recurse -Directory

    $nonDriverFolders = @()

    foreach ($folder in $allFolders) {
        # Check if folder contains any files (ignore empty folders or folders with only subdirs)
        $hasFiles = (Get-ChildItem -Path $folder.FullName -File | Measure-Object).Count -gt 0
        
        if ($hasFiles) {
            # Check if folder contains any .inf files
            $hasInf = (Get-ChildItem -Path $folder.FullName -Filter "*.inf" -File | Measure-Object).Count -gt 0
            
            if (-not $hasInf) {
                $nonDriverFolders += $folder.FullName
            }
        }
    }

    # Convert to relative paths
    $relativePaths = $nonDriverFolders | ForEach-Object {
        # Get path relative to repo root
        $_.Substring($repoRoot.Length + 1)
    }

    # Output to file
    $relativePaths | Out-File -FilePath $outputFile -Encoding utf8

    Write-Host "Found $( $relativePaths.Count ) non-driver folders." -ForegroundColor Green
    Write-Host "List saved to: $outputFile" -ForegroundColor Green
}

Main
