<#
.SYNOPSIS
    Retrieves the Hardware IDs of all present Plug and Play devices on the current system.

.DESCRIPTION
    This script uses `Get-PnpDevice` to list all devices currently present on the system.
    It extracts the Class, FriendlyName, InstanceId, and HardwareIDs for each device.
    The result is exported to 'exports/system_hardware_ids.csv'.
    This is useful for capturing the hardware fingerprint of a reference machine.

.EXAMPLE
    .\scripts\Get-SystemHardwareIDs.ps1
#>

$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
    Main execution function.
#>
function Main {
    $repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
    $outputFile = Join-Path $repoRoot "exports\system_hardware_ids.csv"

    Write-Host "Scanning current system for hardware devices..." -ForegroundColor Cyan

    try {
        # Get all present Plug and Play devices
        # We join the HardwareID array into a single string for CSV compatibility
        $devices = Get-PnpDevice -PresentOnly -ErrorAction Stop | 
            Select-Object Class, FriendlyName, InstanceId, @{Name = "HardwareIDs"; Expression = { $_.HardwareID -join "; " } }

        # Export to CSV
        $devices | Export-Csv -Path $outputFile -NoTypeInformation -Encoding utf8

        Write-Host "Found $( $devices.Count ) devices." -ForegroundColor Green
        Write-Host "Report saved to: $outputFile" -ForegroundColor Green
    } catch {
        Write-Error "Failed to retrieve system hardware IDs: $_"
    }
}

Main
