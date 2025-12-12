<#
.SYNOPSIS
    AutoDeriva System Setup & Driver Installer (Remote/Hybrid Mode)
    
.DESCRIPTION
    This script performs the following actions:
    1. Loads configuration from config.json.
    2. Downloads the driver inventory from the remote repository.
    3. Scans the local system for Hardware IDs.
    4. Matches system devices against the remote driver inventory.
    5. If matches are found:
       - Downloads the file manifest.
       - Downloads all required files for the matched drivers to a temporary directory.
       - Reconstructs the folder structure.
       - Installs drivers using PnPUtil.
    6. Cleans up temporary files.
    
    Features:
    - Auto-elevation (Runs as Administrator)
    - TUI with color-coded output
    - Smart driver matching based on Hardware IDs
    - Remote file fetching (no local drivers folder required)
    - Detailed logging to file and console
    - In-memory caching of inventory and manifest to prevent redundant downloads

.EXAMPLE
    Run from PowerShell:
    .\Install-AutoDeriva.ps1
#>

# ---------------------------------------------------------------------------
# 1. AUTO-ELEVATION
# ---------------------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Requesting administrative privileges..." -ForegroundColor Yellow
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`"" -Verb RunAs -PassThru | Out-Null
    exit
}

$ErrorActionPreference = "Stop"
$Script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$ConfigFile = Join-Path $Script:RepoRoot "config.json"

# ---------------------------------------------------------------------------
# 2. CONFIGURATION & LOGGING
# ---------------------------------------------------------------------------

if (Test-Path $ConfigFile) {
    $Config = Get-Content $ConfigFile | ConvertFrom-Json
} else {
    # Fallback defaults if config is missing (useful for standalone execution)
    $Config = @{
        BaseUrl = "https://raw.githubusercontent.com/supermarsx/autoderiva/main/"
        InventoryPath = "exports/driver_inventory.csv"
        ManifestPath = "exports/driver_file_manifest.csv"
        LogFile = "AutoDeriva.log"
    }
}

$LogFilePath = Join-Path $Script:RepoRoot $Config.LogFile
# Initialize Log
"AutoDeriva Log Started: $(Get-Date)" | Out-File -FilePath $LogFilePath -Encoding utf8 -Force

# TUI Colors
$ColorHeader = "Cyan"
$ColorText = "White"
$ColorAccent = "Blue"
$ColorDim = "Gray"

function Write-BrandHeader {
    Clear-Host
    Write-Host "`n"
    Write-Host "           |           " -ForegroundColor $ColorText
    Write-Host "       ____|____       " -ForegroundColor Yellow
    Write-Host "      /_________\      " -ForegroundColor Yellow
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
    Add-Content -Path $LogFilePath -Value "`n[$Title]"
}

function Write-AutoDerivaLog {
    param(
        [string]$Status,
        [string]$Message,
        [string]$Color = "White"
    )
    # Console Output
    Write-Host "   [" -NoNewline -ForegroundColor $ColorDim
    Write-Host "$Status" -NoNewline -ForegroundColor $Color
    Write-Host "] $Message" -ForegroundColor $ColorText
    
    # File Output
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFilePath -Value "[$timestamp] [$Status] $Message"
}

# ---------------------------------------------------------------------------
# 3. HELPER FUNCTIONS
# ---------------------------------------------------------------------------

# Global cache for downloaded CSVs to avoid re-fetching
$Script:CsvCache = @{}

function Invoke-DownloadFile {
    param($Url, $OutputPath)
    try {
        $dir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        
        # Use Invoke-WebRequest with basic retry logic could be added here
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
        return $true
    }
    catch {
        Write-AutoDerivaLog "ERROR" "Failed to download: $Url. Error: $_" "Red"
        return $false
    }
}

function Get-RemoteCsv {
    param($Url)
    
    # Check cache first
    if ($Script:CsvCache.ContainsKey($Url)) {
        Write-AutoDerivaLog "INFO" "Using cached data for: $Url" "Cyan"
        return $Script:CsvCache[$Url]
    }

    try {
        Write-AutoDerivaLog "INFO" "Fetching data from: $Url" "Cyan"
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
        # Convert CSV content to objects
        $content = $response.Content | ConvertFrom-Csv
        
        # Store in cache
        $Script:CsvCache[$Url] = $content
        
        return $content
    }
    catch {
        Write-AutoDerivaLog "ERROR" "Failed to fetch CSV from $Url" "Red"
        throw $_
    }
}

# ---------------------------------------------------------------------------
# 4. MAIN LOGIC
# ---------------------------------------------------------------------------

try {
    Write-BrandHeader
    Write-AutoDerivaLog "START" "AutoDeriva Installer Initialized" "Green"
    
    # 1. Create Temp Directory
    $TempDir = Join-Path $env:TEMP "AutoDeriva_$(Get-Random)"
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    Write-AutoDerivaLog "INFO" "Temporary workspace: $TempDir" "Gray"

    # 2. Get System Hardware IDs
    Write-Section "Hardware Detection"
    Write-AutoDerivaLog "INFO" "Scanning system devices..." "Cyan"
    $SystemDevices = Get-PnpDevice -PresentOnly
    $SystemHardwareIds = $SystemDevices.HardwareID | Where-Object { $_ } | ForEach-Object { $_.ToUpper() }
    Write-AutoDerivaLog "INFO" "Found $( $SystemHardwareIds.Count ) active hardware IDs." "Green"

    # 3. Fetch Driver Inventory
    Write-Section "Driver Inventory"
    $InventoryUrl = $Config.BaseUrl + $Config.InventoryPath
    $DriverInventory = Get-RemoteCsv -Url $InventoryUrl
    Write-AutoDerivaLog "INFO" "Loaded $( $DriverInventory.Count ) drivers from remote inventory." "Green"

    # 4. Match Drivers
    Write-Section "Driver Matching"
    $DriverMatches = @()
    
    foreach ($driver in $DriverInventory) {
        # Parse HWIDs from CSV (semicolon separated)
        $driverHwids = $driver.HardwareIDs -split ";"
        
        # Check for intersection
        $intersect = $driverHwids | Where-Object { $SystemHardwareIds -contains $_.ToUpper() }
        
        if ($intersect) {
            # Check if we already have a newer version for this device class/provider?
            # For simplicity, we'll collect all matches and let PnPUtil decide or filter duplicates.
            # A better approach is to group by Class/Provider and pick the newest Date/Version.
            
            $DriverMatches += $driver
        }
    }

    if ($DriverMatches.Count -eq 0) {
        Write-AutoDerivaLog "INFO" "No compatible drivers found in the inventory." "Yellow"
    }
    else {
        Write-AutoDerivaLog "SUCCESS" "Found $( $DriverMatches.Count ) compatible drivers." "Green"
        
        # 5. Fetch File Manifest
        Write-Section "File Manifest & Download"
        $ManifestUrl = $Config.BaseUrl + $Config.ManifestPath
        # This call will cache the manifest if called multiple times (though here it's called once)
        $FileManifest = Get-RemoteCsv -Url $ManifestUrl
        
        # Group matches by INF path to avoid duplicate downloads
        $UniqueInfs = $DriverMatches | Select-Object -ExpandProperty InfPath -Unique
        
        $DownloadedFiles = 0
        
        foreach ($infPath in $UniqueInfs) {
            Write-AutoDerivaLog "PROCESS" "Processing driver: $infPath" "Cyan"
            
            # Find all files associated with this INF in the manifest
            # Note: AssociatedInf in manifest uses forward slashes, ensure matching format
            $TargetInf = $infPath.Replace('\', '/')
            $DriverFiles = $FileManifest | Where-Object { $_.AssociatedInf -eq $TargetInf }
            
            if (-not $DriverFiles) {
                Write-AutoDerivaLog "WARN" "No files found in manifest for $infPath" "Yellow"
                continue
            }
            
            foreach ($file in $DriverFiles) {
                $remoteUrl = $Config.BaseUrl + $file.RelativePath
                # Reconstruct path in TempDir
                $localPath = Join-Path $TempDir $file.RelativePath.Replace('/', '\')
                
                # Write-AutoDerivaLog "DOWN" "Downloading $($file.RelativePath)..." "Gray"
                $success = Invoke-DownloadFile -Url $remoteUrl -OutputPath $localPath
                if ($success) { $DownloadedFiles++ }
            }
            
            # 6. Install Driver
            # The INF file is at $TempDir + $infPath
            $LocalInfPath = Join-Path $TempDir $infPath.Replace('/', '\')
            
            if (Test-Path $LocalInfPath) {
                Write-AutoDerivaLog "INSTALL" "Installing driver..." "Cyan"
                $proc = Start-Process -FilePath "pnputil.exe" -ArgumentList "/add-driver `"$LocalInfPath`" /install" -NoNewWindow -Wait -PassThru
                
                if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) { # 3010 = Reboot required
                    Write-AutoDerivaLog "SUCCESS" "Driver installed successfully." "Green"
                } else {
                    Write-AutoDerivaLog "ERROR" "Driver installation failed. Exit Code: $($proc.ExitCode)" "Red"
                }
            } else {
                Write-AutoDerivaLog "ERROR" "INF file not found after download: $LocalInfPath" "Red"
            }
        }
    }

    # 7. Cleanup
    Write-Section "Cleanup"
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force
        Write-AutoDerivaLog "INFO" "Temporary files removed." "Green"
    }

    Write-Section "Completion"
    Write-AutoDerivaLog "DONE" "AutoDeriva process completed." "Green"
    Write-AutoDerivaLog "INFO" "Log saved to: $LogFilePath" "Gray"
    
    # Pause to let user see output
    Read-Host "Press Enter to exit..."

} catch {
    Write-AutoDerivaLog "FATAL" "An unexpected error occurred: $_" "Red"
    Write-AutoDerivaLog "FATAL" $($_.ScriptStackTrace) "Red"
    Read-Host "Press Enter to exit..."
}
