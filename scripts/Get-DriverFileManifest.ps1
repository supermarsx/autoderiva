<#
.SYNOPSIS
    Generates a file manifest for all files in the drivers directory.

.DESCRIPTION
    This script recursively lists all files in the 'drivers' directory.
    For each file, it calculates the relative path and finds the nearest parent .inf file.
    This association allows the installer to know which files belong to which driver package.
    The output is saved to 'exports/driver_file_manifest.csv'.

.EXAMPLE
    .\scripts\Get-DriverFileManifest.ps1
#>

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$driversPath = Join-Path $repoRoot "drivers"
$outputFile = Join-Path $repoRoot "exports\driver_file_manifest.csv"

Write-Host "Scanning for all files in: $driversPath"

if (-not (Test-Path $driversPath)) {
    Write-Error "Drivers directory not found!"
}

$files = Get-ChildItem -Path $driversPath -Recurse -File

$results = $files | ForEach-Object {
    $file = $_
    # Calculate relative path (e.g., drivers/gw1-w149/...)
    $relPath = $file.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
    
    # Find nearest .inf file by walking up the directory tree
    $currentDir = $file.Directory
    $associatedInf = $null
    
    while ($true) {
        $infFiles = Get-ChildItem -Path $currentDir.FullName -Filter "*.inf" -File
        if ($infFiles) {
            # Found one or more INFs. Use the first one or join them.
            $associatedInf = ($infFiles | ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/') }) -join ";"
            break
        }
        
        # Stop if we have reached the drivers root
        if ($currentDir.FullName -eq $driversPath) { break }
        
        $currentDir = $currentDir.Parent
        if ($null -eq $currentDir) { break }
        
        # Safety break if we somehow went above drivers path
        if ($currentDir.FullName.Length -lt $driversPath.Length) { break }
    }

    [PSCustomObject]@{
        RelativePath  = $relPath
        Size          = $file.Length
        AssociatedInf = $associatedInf
    }
}

$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding utf8

Write-Host "Manifest complete. Found $( $results.Count ) files."
Write-Host "Saved to: $outputFile"
