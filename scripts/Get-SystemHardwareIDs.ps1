$ErrorActionPreference = "Stop"

# Determine paths
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$outputFile = Join-Path $repoRoot "system_hardware_ids.csv"

Write-Host "Scanning current system for hardware devices..."

# Get all present Plug and Play devices
# We join the HardwareID array into a single string for CSV compatibility
$devices = Get-PnpDevice -PresentOnly | 
Select-Object Class, FriendlyName, InstanceId, @{Name = "HardwareIDs"; Expression = { $_.HardwareID -join "; " } }

# Export to CSV
$devices | Export-Csv -Path $outputFile -NoTypeInformation -Encoding utf8

Write-Host "Found $( $devices.Count ) devices."
Write-Host "Report saved to: $outputFile"
