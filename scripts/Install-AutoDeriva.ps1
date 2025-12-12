<#
.SYNOPSIS
    AutoDeriva System Setup & Driver Installer
    
.DESCRIPTION
    This script performs the following actions:
    1. Copies the 'cuco' utility to the current user's Desktop.
    2. Scans the local 'drivers' repository for drivers compatible with the current system.
    3. Identifies the most recent version of compatible drivers from the library.
    4. Installs/Updates the drivers using PnPUtil.
    
    Features:
    - Auto-elevation (Runs as Administrator)
    - TUI with color-coded output
    - Smart driver matching based on Hardware IDs
    - Version/Date comparison to ensure latest drivers are used
    
.EXAMPLE
    Run from PowerShell:
    .\Install-AutoDeriva.ps1
    
    One-line execution (if hosted):
    irm https://raw.githubusercontent.com/supermarsx/autoderiva/main/scripts/Install-AutoDeriva.ps1 | iex
#>

# ---------------------------------------------------------------------------
# 1. AUTO-ELEVATION
# ---------------------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Requesting administrative privileges..." -ForegroundColor Yellow
    $newProcess = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`"" -Verb RunAs -PassThru
    exit
}

$ErrorActionPreference = "Stop"
$Script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path

# ---------------------------------------------------------------------------
# 2. TUI HELPER FUNCTIONS
# ---------------------------------------------------------------------------
function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO]    $Message" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-WarningLog {
    param([string]$Message)
    Write-Host "[WARN]    $Message" -ForegroundColor Yellow
}

function Write-ErrorLog {
    param([string]$Message)
    Write-Host "[ERROR]   $Message" -ForegroundColor Red
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n-> $Message" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# 3. CORE TASKS
# ---------------------------------------------------------------------------

function Copy-CucoToDesktop {
    Write-Header "Task 1: Copy Cuco Utility"
    
    $sourcePath = Join-Path $Script:RepoRoot "cuco\CtoolGui.exe"
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $destPath = Join-Path $desktopPath "CtoolGui.exe"

    if (-not (Test-Path $sourcePath)) {
        Write-ErrorLog "Source file not found: $sourcePath"
        return
    }

    Write-Info "Source: $sourcePath"
    Write-Info "Dest:   $destPath"

    try {
        Copy-Item -Path $sourcePath -Destination $destPath -Force
        if (Test-Path $destPath) {
            Write-Success "CtoolGui.exe copied to Desktop successfully."
        } else {
            Write-ErrorLog "Failed to verify file at destination."
        }
    } catch {
        Write-ErrorLog "Copy failed: $_"
    }
}

function Install-Drivers {
    Write-Header "Task 2: Smart Driver Installation"

    $driversPath = Join-Path $Script:RepoRoot "drivers"
    if (-not (Test-Path $driversPath)) {
        Write-ErrorLog "Drivers folder not found at: $driversPath"
        return
    }

    # A. Get System Hardware IDs
    Write-Step "Scanning System Hardware..."
    $pnpDevices = Get-PnpDevice -PresentOnly
    $systemHwIds = New-Object System.Collections.Generic.HashSet[string]
    
    foreach ($dev in $pnpDevices) {
        if ($dev.HardwareID) {
            foreach ($id in $dev.HardwareID) {
                $null = $systemHwIds.Add($id.ToUpper())
            }
        }
    }
    Write-Info "Found $( $systemHwIds.Count ) unique Hardware IDs on this system."

    # B. Scan Library for Compatible Drivers
    Write-Step "Scanning Driver Library (this may take a moment)..."
    $infFiles = Get-ChildItem -Path $driversPath -Recurse -Filter "*.inf"
    
    $compatibleDrivers = @() # List of objects { Path, Date, Version, MatchedID }

    # Regex for parsing
    $hwidRegex = [Regex]"(PCI|USB|ACPI|HID|HDAUDIO|BTH|DISPLAY|INTELAUDIO)\\[A-Za-z0-9&_]+"
    
    foreach ($inf in $infFiles) {
        try {
            # Read file content (first 500 lines usually enough for IDs, but read all to be safe)
            # Optimization: Read as string array to avoid massive memory alloc for huge files
            $content = Get-Content -Path $inf.FullName -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            $text = $content -join "`n"

            # 1. Check for HWID match first (fastest fail)
            $matches = $hwidRegex.Matches($text)
            $matchedId = $null
            $isCompatible = $false

            foreach ($m in $matches) {
                if ($systemHwIds.Contains($m.Value.ToUpper())) {
                    $isCompatible = $true
                    $matchedId = $m.Value.ToUpper()
                    break # Found at least one match, this INF is relevant
                }
            }

            if ($isCompatible) {
                # 2. Parse Date/Version if compatible
                $date = [DateTime]::MinValue
                $version = "0.0.0.0"
                
                # Simple regex for DriverVer
                if ($text -match "(?m)^\s*DriverVer\s*=\s*(.*)$") {
                    $verStr = $matches[1].Trim().Trim('"')
                    $parts = $verStr -split ","
                    try { $date = [DateTime]::Parse($parts[0].Trim()) } catch {}
                    if ($parts.Count -gt 1) { $version = $parts[1].Trim() }
                }

                $compatibleDrivers += [PSCustomObject]@{
                    Path = $inf.FullName
                    Name = $inf.Name
                    Date = $date
                    Version = $version
                    MatchedID = $matchedId
                }
                # Write-Host "." -NoNewline -ForegroundColor DarkGray
            }
        } catch {
            Write-WarningLog "Error reading $($inf.Name)"
        }
    }
    Write-Host "" # Newline after dots

    if ($compatibleDrivers.Count -eq 0) {
        Write-WarningLog "No compatible drivers found in the library."
        return
    }

    Write-Success "Found $( $compatibleDrivers.Count ) compatible driver files."

    # C. Select Best Drivers
    # Group by MatchedID (or just install all unique compatible INFs? 
    # Better: For each compatible INF, we want to install it. 
    # But if we have multiple INFs for the SAME ID, we should pick the newest.)
    
    Write-Step "Selecting best versions..."
    
    # We group by the INF file path to ensure uniqueness first, then we need to filter.
    # Actually, if multiple INFs serve the same ID, we want the best one.
    # Strategy: Group by MatchedID. Pick top 1 for each ID. Collect those INFs.
    
    $bestInfs = @{} # Key: INF Path, Value: DriverObject

    $grouped = $compatibleDrivers | Group-Object MatchedID
    foreach ($g in $grouped) {
        # Sort by Date Desc, then Version Desc
        $best = $g.Group | Sort-Object Date, Version -Descending | Select-Object -First 1
        $bestInfs[$best.Path] = $best
    }

    $finalList = $bestInfs.Values | Sort-Object Date
    Write-Info "Selected $( $finalList.Count ) unique driver packages to install."

    # D. Install
    Write-Step "Installing Drivers..."
    
    foreach ($drv in $finalList) {
        Write-Host "Installing: " -NoNewline
        Write-Host "$($drv.Name)" -ForegroundColor Cyan -NoNewline
        Write-Host " [$($drv.Date.ToShortDateString()) - v$($drv.Version)]" -ForegroundColor DarkGray
        
        $args = @("/add-driver", "`"$($drv.Path)`"", "/install")
        
        $p = Start-Process -FilePath "pnputil.exe" -ArgumentList $args -NoNewWindow -Wait -PassThru
        
        if ($p.ExitCode -eq 0) {
            Write-Success "Installed successfully."
        } elseif ($p.ExitCode -eq 259) {
            Write-Success "Installed (Reboot required)."
        } elseif ($p.ExitCode -eq 1) {
             Write-WarningLog "Not needed (Newer or same version already installed)."
        } else {
            Write-ErrorLog "Failed with exit code $($p.ExitCode)."
        }
    }
}

# ---------------------------------------------------------------------------
# 4. MAIN EXECUTION
# ---------------------------------------------------------------------------
Clear-Host
Write-Header "AutoDeriva Installer"
Write-Info "Time: $(Get-Date)"
Write-Info "User: $env:USERNAME"
Write-Info "Repo: $Script:RepoRoot"

Copy-CucoToDesktop
Install-Drivers

Write-Header "Installation Complete"
Write-Info "Please reboot your system if any drivers requested it."
Write-Host "`nPress any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
