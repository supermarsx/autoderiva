$ErrorActionPreference = "Stop"

# Get-DriverInventory.ps1
# Scans all .inf files under the `drivers` folder and produces a CSV inventory

# Determine paths
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$driversPath = Join-Path $repoRoot "drivers"
$outputFile = Join-Path $repoRoot "driver_inventory.csv"

Write-Host "Scanning for drivers in: $driversPath"

$infFiles = Get-ChildItem -Path $driversPath -Recurse -Filter "*.inf"
$results = @()

foreach ($inf in $infFiles) {
    Write-Host "Processing $($inf.Name)..." -ForegroundColor Gray
    
    try {
        $content = Get-Content -Path $inf.FullName -ErrorAction Stop
        $text = $content -join "`n"

        # Helper to extract value by key in [Version] section
        function Get-InfValue ($key) {
            if ($text -match "(?m)^\s*$key\s*=\s*(.*)$") {
                return $matches[1].Trim().Trim('"')
            }
            return $null
        }

        # Extract Basic Info
        $class = Get-InfValue "Class"
        $provider = Get-InfValue "Provider"
        $driverVerRaw = Get-InfValue "DriverVer"
        
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

        $results += [PSCustomObject]@{
            FileName      = $inf.Name
            RelativePath  = $inf.FullName.Substring($repoRoot.Length + 1)
            Class         = $class
            Provider      = $provider
            Date          = $date
            Version       = $version
            HardwareIDs   = ($hwids -join "; ")
        }
    }
    catch {
        Write-Warning "Failed to process $($inf.Name): $_"
    }
}

# Export to CSV
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding utf8

Write-Host "Inventory complete. Found $( $results.Count ) drivers."
Write-Host "Report saved to: $outputFile"
