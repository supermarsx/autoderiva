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

function Get-DeviceHardwareIdMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$InstanceIds,
        [int]$MaxConcurrency = 8
    )

    $map = @{}
    foreach ($id in $InstanceIds) { if ($id) { $map[$id] = @() } }
    if ($map.Count -eq 0) { return $map }

    $runspacePool = $null
    try {
        $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, $MaxConcurrency)
        $runspacePool.Open()

        $jobs = New-Object System.Collections.Generic.List[object]
        foreach ($id in $map.Keys) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $runspacePool
            $null = $ps.AddScript({
                param($instanceId)
                try {
                    Import-Module PnpDevice -ErrorAction SilentlyContinue | Out-Null
                    $dev = Get-PnpDevice -InstanceId $instanceId -ErrorAction Stop
                    $hw = $null
                    if ($dev -and ($dev.PSObject.Properties.Name -contains 'HardwareID')) { $hw = $dev.HardwareID }
                    if (-not $hw) {
                        try {
                            $p = Get-PnpDeviceProperty -InstanceId $instanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop
                            $hw = $p.Data
                        }
                        catch { $hw = $null }
                    }
                    $vals = @()
                    if ($hw) { $vals = @($hw | Where-Object { $_ }) }
                    return [PSCustomObject]@{ InstanceId = $instanceId; HardwareIds = $vals }
                }
                catch {
                    return [PSCustomObject]@{ InstanceId = $instanceId; HardwareIds = @() }
                }
            }).AddArgument($id)

            $handle = $ps.BeginInvoke()
            $jobs.Add([PSCustomObject]@{ PowerShell = $ps; Handle = $handle })
        }

        foreach ($job in $jobs) {
            try {
                $out = $job.PowerShell.EndInvoke($job.Handle)
                if ($out -and $out.InstanceId) {
                    $map[$out.InstanceId] = @($out.HardwareIds)
                }
            }
            finally {
                try { $job.PowerShell.Dispose() } catch { Write-Verbose "Failed to dispose PowerShell job: $_" }
            }
        }
    }
    catch {
        Write-Verbose "Parallel hardware-id query unavailable; falling back to single. Error: $_"
        foreach ($id in $map.Keys) {
            try {
                $dev = Get-PnpDevice -InstanceId $id -ErrorAction Stop
                $hw = $null
                if ($dev -and ($dev.PSObject.Properties.Name -contains 'HardwareID')) { $hw = $dev.HardwareID }
                $map[$id] = @($hw | Where-Object { $_ })
            }
            catch { $map[$id] = @() }
        }
    }
    finally {
        if ($runspacePool) {
            try { $runspacePool.Close() } catch { Write-Verbose "Failed to close RunspacePool: $_" }
            try { $runspacePool.Dispose() } catch { Write-Verbose "Failed to dispose RunspacePool: $_" }
        }
    }

    return $map
}

<#
.SYNOPSIS
    Main execution function.
#>
function Main {
    $repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
    $outputFile = Join-Path $repoRoot "exports\system_hardware_ids.csv"

    Write-Host "Scanning current system for hardware devices..." -ForegroundColor Cyan

    try {
        # Get all present Plug and Play devices.
        # Fetch Hardware IDs in parallel per InstanceId (faster on systems with many devices).
        $base = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Select-Object Class, FriendlyName, InstanceId)
        $ids = @($base | Where-Object { $_.InstanceId } | ForEach-Object { $_.InstanceId })
        $hwMap = Get-DeviceHardwareIdMap -InstanceIds $ids -MaxConcurrency 8

        $devices = foreach ($d in $base) {
            $hw = @()
            if ($d.InstanceId -and $hwMap.ContainsKey($d.InstanceId)) { $hw = @($hwMap[$d.InstanceId]) }
            [PSCustomObject]@{
                Class        = $d.Class
                FriendlyName = $d.FriendlyName
                InstanceId   = $d.InstanceId
                HardwareIDs  = ($hw -join '; ')
            }
        }

        # Export to CSV
        $devices | Export-Csv -Path $outputFile -NoTypeInformation -Encoding utf8

        Write-Host "Found $( $devices.Count ) devices." -ForegroundColor Green
        Write-Host "Report saved to: $outputFile" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to retrieve system hardware IDs: $_"
    }
}

Main
