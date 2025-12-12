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

<#
.SYNOPSIS
    Finds the nearest parent INF file for a given file.
.PARAMETER File
    The FileInfo object to start searching from.
.PARAMETER DriversPath
    The root drivers path to stop searching at.
.PARAMETER RepoRoot
    The repository root for relative path calculation.
.OUTPUTS
    String. The relative path(s) to the associated INF file(s), semicolon separated.
#>
function Find-AssociatedInf {
    param($File, $DriversPath, $RepoRoot)
    
    $currentDir = $File.Directory
    $associatedInf = $null
    
    while ($true) {
        $infFiles = Get-ChildItem -Path $currentDir.FullName -Filter "*.inf" -File
        if ($infFiles) {
            # Found one or more INFs. Use the first one or join them.
            $associatedInf = ($infFiles | ForEach-Object { $_.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/') }) -join ";"
            break
        }
        
        # Stop if we have reached the drivers root
        if ($currentDir.FullName -eq $DriversPath) { break }
        
        $currentDir = $currentDir.Parent
        if ($null -eq $currentDir) { break }
        
        # Safety break if we somehow went above drivers path
        if ($currentDir.FullName.Length -lt $DriversPath.Length) { break }
    }
    
    return $associatedInf
}

<#
.SYNOPSIS
    Main execution function.
#>
function Main {
    $repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
    $driversPath = Join-Path $repoRoot "drivers"
    $outputFile = Join-Path $repoRoot "exports\driver_file_manifest.csv"

    Write-Host "Scanning for all files in: $driversPath" -ForegroundColor Cyan

    if (-not (Test-Path $driversPath)) {
        Write-Error "Drivers directory not found!"
        return
    }

    $files = Get-ChildItem -Path $driversPath -Recurse -File
    $results = @()

    foreach ($file in $files) {
        # Calculate relative path (e.g., drivers/gw1-w149/...)
        $relPath = $file.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
        
        $associatedInf = Find-AssociatedInf -File $file -DriversPath $driversPath -RepoRoot $repoRoot

        $results += [PSCustomObject]@{
            RelativePath  = $relPath
            Size          = $file.Length
            AssociatedInf = $associatedInf
        }
    }

    $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding utf8

    Write-Host "Manifest complete. Found $( $results.Count ) files." -ForegroundColor Green
    Write-Host "Saved to: $outputFile" -ForegroundColor Green
}

Main
