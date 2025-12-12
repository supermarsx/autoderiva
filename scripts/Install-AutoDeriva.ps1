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

    Supported School Models:
    - Insys GW1-W149 (14" i3-10110U)
    - HP 240 G8 Notebook PC
    - JP-IK Leap T304 (SF20PA6W)
    
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
# 2. TUI HELPER FUNCTIONS (Blue Theme)
# ---------------------------------------------------------------------------
$ColorHeader = "Cyan"
$ColorText = "White"
$ColorAccent = "Blue"
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"
$ColorDim = "Gray"

function Write-BrandHeader {
    Clear-Host
    Write-Host "`n"
    
    # Life Raft ASCII Art
    Write-Host "           |           " -ForegroundColor $ColorText
    Write-Host "       ____|____       " -ForegroundColor $ColorWarning
    Write-Host "      /_________\      " -ForegroundColor $ColorWarning
    Write-Host "   ~~~~~~~~~~~~~~~~~   " -ForegroundColor $ColorAccent
    
    Write-Host "   AUTO" -NoNewline -ForegroundColor $ColorAccent
    Write-Host "DERIVA" -ForegroundColor $ColorHeader
    Write-Host "   System Setup & Driver Installer" -ForegroundColor $ColorDim
    Write-Host "   " ("-" * 60) -ForegroundColor $ColorAccent
    Write-Host "`n"
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n   [$Title]" -ForegroundColor $ColorHeader
    Write-Host "   " ("-" * ($Title.Length + 2)) -ForegroundColor $ColorAccent
}

function Write-Log {
    param(
        [string]$Status,
        [string]$Message,
        [string]$Color = "White"
    )
    # Format: [STATUS] Message
    Write-Host "   [" -NoNewline -ForegroundColor $ColorDim
    Write-Host "$Status" -NoNewline -ForegroundColor $Color
    Write-Host "] $Message" -ForegroundColor $ColorText
}

# ---------------------------------------------------------------------------
# 3. CORE TASKS
# ---------------------------------------------------------------------------

function Copy-CucoToDesktop {
    Write-Section "Task 1: Copy Cuco Utility"
    
    $sourcePath = Join-Path $Script:RepoRoot "cuco\CtoolGui.exe"
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $destPath = Join-Path $desktopPath "CtoolGui.exe"

    if (-not (Test-Path $sourcePath)) {
        Write-Log "ERROR" "Source file not found: $sourcePath" "Red"
        return
    }

    try {
        Copy-Item -Path $sourcePath -Destination $destPath -Force
        if (Test-Path $destPath) {
            Write-Log "DONE" "CtoolGui.exe copied to Desktop." "Green"
        }
        else {
            Write-Log "FAIL" "Failed to verify file at destination." "Red"
        }
    }
    catch {
        Write-Log "FAIL" "Copy failed: $_" "Red"
    }
}

function Install-Drivers {
    Write-Section "Task 2: Smart Driver Installation"

    $driversPath = Join-Path $Script:RepoRoot "drivers"
    if (-not (Test-Path $driversPath)) {
        Write-Log "ERROR" "Drivers folder not found at: $driversPath" "Red"
        return
    }

    # A. Get System Hardware IDs
    Write-Log "INFO" "Scanning System Hardware..." "Cyan"
    $pnpDevices = Get-PnpDevice -PresentOnly
    $systemHwIds = New-Object System.Collections.Generic.HashSet[string]
    
    foreach ($dev in $pnpDevices) {
        if ($dev.HardwareID) {
            foreach ($id in $dev.HardwareID) {
                $null = $systemHwIds.Add($id.ToUpper())
            }
        }
    }
    Write-Log "INFO" "Found $( $systemHwIds.Count ) unique Hardware IDs." "Gray"

    # B. Scan Library for Compatible Drivers
    Write-Log "INFO" "Scanning Driver Library..." "Cyan"
    
    $infFiles = Get-ChildItem -Path $driversPath -Recurse -Filter "*.inf"
    $totalFiles = $infFiles.Count
    $compatibleDrivers = @() 
    $hwidRegex = [Regex]"(PCI|USB|ACPI|HID|HDAUDIO|BTH|DISPLAY|INTELAUDIO)\\[A-Za-z0-9&_]+"
    
    $i = 0
    foreach ($inf in $infFiles) {
        $i++
        $percent = [math]::Min(100, [int](($i / $totalFiles) * 100))
        Write-Progress -Activity "Scanning Driver Library" -Status "Processing $($inf.Name)" -PercentComplete $percent

        try {
            # Read file content (first 2000 chars usually enough for IDs to appear)
            # Reading full content is safer but slower.
            $content = Get-Content -Path $inf.FullName -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            $text = $content -join "`n"

            # 1. Check for HWID match
            $matches = $hwidRegex.Matches($text)
            $matchedId = $null
            $isCompatible = $false

            foreach ($m in $matches) {
                if ($systemHwIds.Contains($m.Value.ToUpper())) {
                    $isCompatible = $true
                    $matchedId = $m.Value.ToUpper()
                    break 
                }
            }

            if ($isCompatible) {
                # 2. Parse Date/Version
                $date = [DateTime]::MinValue
                $version = "0.0.0.0"
                
                if ($text -match "(?m)^\s*DriverVer\s*=\s*(.*)$") {
                    $verStr = $matches[1].Trim().Trim('"')
                    $parts = $verStr -split ","
                    try { $date = [DateTime]::Parse($parts[0].Trim()) } catch {}
                    if ($parts.Count -gt 1) { $version = $parts[1].Trim() }
                }

                $compatibleDrivers += [PSCustomObject]@{
                    Path      = $inf.FullName
                    Name      = $inf.Name
                    Date      = $date
                    Version   = $version
                    MatchedID = $matchedId
                }
            }
        }
        catch {}
    }
    Write-Progress -Activity "Scanning Driver Library" -Completed

    if ($compatibleDrivers.Count -eq 0) {
        Write-Log "WARN" "No compatible drivers found in the library." "Yellow"
        return
    }

    Write-Log "INFO" "Found $( $compatibleDrivers.Count ) compatible driver files." "Gray"

    # C. Select Best Drivers
    Write-Log "INFO" "Selecting best versions..." "Cyan"
    
    $bestInfs = @{} 
    $grouped = $compatibleDrivers | Group-Object MatchedID
    foreach ($g in $grouped) {
        # Sort by Date Desc, then Version Desc
        $best = $g.Group | Sort-Object Date, Version -Descending | Select-Object -First 1
        $bestInfs[$best.Path] = $best
    }

    $finalList = $bestInfs.Values | Sort-Object Date
    Write-Log "INFO" "Selected $( $finalList.Count ) unique driver packages to install." "Gray"

    # D. Install
    Write-Section "Installing Drivers"
    
    $stats = @{ Installed = 0; Skipped = 0; Failed = 0; Total = $finalList.Count }
    $j = 0

    foreach ($drv in $finalList) {
        $j++
        $percent = [int](($j / $stats.Total) * 100)
        Write-Progress -Activity "Installing Drivers" -Status "Installing $($drv.Name)" -PercentComplete $percent -CurrentOperation "$j of $($stats.Total)"

        $args = @("/add-driver", "`"$($drv.Path)`"", "/install")
        $p = Start-Process -FilePath "pnputil.exe" -ArgumentList $args -NoNewWindow -Wait -PassThru
        
        if ($p.ExitCode -eq 0) {
            Write-Log "DONE" "$($drv.Name)" "Green"
            $stats.Installed++
        }
        elseif ($p.ExitCode -eq 259) {
            Write-Log "DONE" "$($drv.Name) (Reboot Req)" "Green"
            $stats.Installed++
        }
        elseif ($p.ExitCode -eq 1) {
            Write-Log "SKIP" "$($drv.Name) (Up to date)" "Yellow"
            $stats.Skipped++
        }
        else {
            Write-Log "FAIL" "$($drv.Name) (Code $($p.ExitCode))" "Red"
            $stats.Failed++
        }
    }
    Write-Progress -Activity "Installing Drivers" -Completed

    # Summary
    Write-Section "Summary"
    Write-Log "INFO" "Total:     $($stats.Total)" "White"
    Write-Log "INFO" "Installed: $($stats.Installed)" "Green"
    Write-Log "INFO" "Skipped:   $($stats.Skipped)" "Yellow"
    Write-Log "INFO" "Failed:    $($stats.Failed)" "Red"
}

# ---------------------------------------------------------------------------
# 4. MAIN EXECUTION
# ---------------------------------------------------------------------------
Write-BrandHeader
Write-Log "INFO" "Time: $(Get-Date)" "Gray"
Write-Log "INFO" "User: $env:USERNAME" "Gray"
Write-Log "INFO" "Repo: $Script:RepoRoot" "Gray"

Copy-CucoToDesktop
Install-Drivers

Write-Section "Complete"
Write-Log "INFO" "Please reboot your system if any drivers requested it." "Cyan"
Write-Host "`n   Press any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
