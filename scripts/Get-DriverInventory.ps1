<#
.SYNOPSIS
    Generates a detailed inventory of all drivers in the repository.

.DESCRIPTION
    This script scans all .inf files in the 'drivers' directory.
    It parses each .inf file to extract:
    - Class
    - Provider
    - Driver Version
    - Driver Date
    - Hardware IDs
    
    The results are exported to 'exports/driver_inventory.csv'.
    This inventory is used by the installer script to match drivers to hardware.

.EXAMPLE
    .\scripts\Get-DriverInventory.ps1
#>

$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
    Extracts a value from an INF file content based on a key.
.PARAMETER Text
    The full text content of the INF file.
.PARAMETER Key
    The key to search for (e.g., "Class", "Provider").
.OUTPUTS
    String. The value associated with the key, or null if not found.
#>
function Get-InfValue {
    param($Text, $Key)
    if ($Text -match "(?m)^\s*$Key\s*=\s*(.*)$") {
        return $matches[1].Trim().Trim('"')
    }
    return $null
}

<#
.SYNOPSIS
    Parses a single INF file to extract driver information.
.PARAMETER InfFile
    The FileInfo object representing the INF file.
.PARAMETER RepoRoot
    The root path of the repository (for relative path calculation).
.OUTPUTS
    PSCustomObject. An object containing driver details.
#>
function Get-InfData {
    param($InfFile, $RepoRoot)
    
    try {
        $content = Get-Content -Path $InfFile.FullName -ErrorAction Stop
        $text = $content -join "`n"

        # Extract Basic Info
        $class = Get-InfValue -Text $text -Key "Class"
        $provider = Get-InfValue -Text $text -Key "Provider"
        $driverVerRaw = Get-InfValue -Text $text -Key "DriverVer"
        
        $date = $null
        $version = $null
        
        if ($driverVerRaw) {
            $parts = $driverVerRaw -split ","
            $date = $parts[0].Trim()
            if ($parts.Count -gt 1) {
                $version = $parts[1].Trim()
            }
        }

        # Extract Hardware IDs (Simple heuristic scan)
        $hwidPattern = "(PCI|USB|ACPI|HID|HDAUDIO|BTH|DISPLAY|INTELAUDIO)\\[A-Za-z0-9_&-]+"
        $hwids = [Regex]::Matches($text, $hwidPattern, "IgnoreCase") | 
        ForEach-Object { $_.Value.ToUpper() } | 
        Select-Object -Unique

        return [PSCustomObject]@{
            FileName    = $InfFile.Name
            InfPath     = $InfFile.FullName.Substring($RepoRoot.Length + 1) # Renamed to InfPath for clarity
            Class       = $class
            Provider    = $provider
            Date        = $date
            Version     = $version
            HardwareIDs = ($hwids -join ";") # Removed space for cleaner parsing
        }
    }
    catch {
        Write-Warning "Failed to process $($InfFile.Name): $_"
        return $null
    }
}

<#
.SYNOPSIS
    Main execution function.
#>
function Main {
    $repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
    $driversPath = Join-Path $repoRoot "drivers"
    $outputFile = Join-Path $repoRoot "exports\driver_inventory.csv"

    Write-Host "Scanning for drivers in: $driversPath" -ForegroundColor Cyan

    if (-not (Test-Path $driversPath)) {
        Write-Error "Drivers directory not found!"
        return
    }

    $infFiles = Get-ChildItem -Path $driversPath -Recurse -Filter "*.inf"
    $results = @()

    foreach ($inf in $infFiles) {
        Write-Host "Processing $($inf.Name)..." -ForegroundColor Gray
        $driverInfo = Get-InfData -InfFile $inf -RepoRoot $repoRoot
        if ($driverInfo) {
            $results += $driverInfo
        }
    }

    # Export to CSV
    $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding utf8

    Write-Host "Inventory complete. Found $( $results.Count ) drivers." -ForegroundColor Green
    Write-Host "Report saved to: $outputFile" -ForegroundColor Green
}

Main
