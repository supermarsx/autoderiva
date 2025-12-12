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

# Set Console Colors
$Host.UI.RawUI.BackgroundColor = "DarkBlue"
$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

$ErrorActionPreference = "Stop"
$Script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$ConfigFile = Join-Path $Script:RepoRoot "config.json"

# ---------------------------------------------------------------------------
# 2. CONFIGURATION & LOGGING
# ---------------------------------------------------------------------------

# Default Configuration (Fallback)
$DefaultConfig = @{
    BaseUrl = "https://raw.githubusercontent.com/supermarsx/autoderiva/main/"
    InventoryPath = "exports/driver_inventory.csv"
    ManifestPath = "exports/driver_file_manifest.csv"
    EnableLogging = $false
    LogLevel = "INFO"
    DownloadAllFiles = $false
    CucoBinaryPath = "cuco/CtoolGui.exe"
}

# Try to load local config first
if (Test-Path $ConfigFile) {
    Write-Host "Loading local configuration from $ConfigFile..." -ForegroundColor Cyan
    try {
        $LocalConfig = Get-Content $ConfigFile | ConvertFrom-Json
        # Merge with defaults (simple overlay)
        $Config = $DefaultConfig.Clone()
        foreach ($prop in $LocalConfig.PSObject.Properties) {
            $Config[$prop.Name] = $prop.Value
        }
    } catch {
        Write-Warning "Failed to parse local config. Using defaults."
        $Config = $DefaultConfig
    }
} else {
    # Try to fetch remote config
    $RemoteConfigUrl = "https://raw.githubusercontent.com/supermarsx/autoderiva/main/config.json"
    Write-Host "Local config not found. Attempting to fetch remote config from $RemoteConfigUrl..." -ForegroundColor Cyan
    try {
        $RemoteConfigJson = Invoke-WebRequest -Uri $RemoteConfigUrl -UseBasicParsing -ErrorAction Stop
        $RemoteConfig = $RemoteConfigJson.Content | ConvertFrom-Json
        
        $Config = $DefaultConfig.Clone()
        foreach ($prop in $RemoteConfig.PSObject.Properties) {
            $Config[$prop.Name] = $prop.Value
        }
        Write-Host "Successfully loaded remote configuration." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to fetch remote config. Using internal defaults."
        $Config = $DefaultConfig
    }
}

# Initialize Stats
$Script:Stats = @{
    StartTime = Get-Date
    DriversScanned = 0
    DriversMatched = 0
    FilesDownloaded = 0
    DriversInstalled = 0
    DriversFailed = 0
    RebootsRequired = 0
}

# Initialize Log
if ($Config.EnableLogging) {
    $LogFileName = "autoderiva-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $LogFilePath = Join-Path $Script:RepoRoot $LogFileName
    try {
        "AutoDeriva Log Started: $(Get-Date)" | Out-File -FilePath $LogFilePath -Encoding utf8 -Force
        Write-Host "Logging enabled. Log file: $LogFilePath" -ForegroundColor Gray
    } catch {
        Write-Warning "Could not write to log file at $LogFilePath. Logging to console only."
        $LogFilePath = $null
    }
} else {
    $LogFilePath = $null
}

# TUI Colors
$ColorHeader = "Cyan"
$ColorText = "White"
$ColorAccent = "Blue"
$ColorDim = "Gray"

<#
.SYNOPSIS
    Displays the AutoDeriva brand header.
.DESCRIPTION
    Clears the host and prints the ASCII art logo and title.
#>
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

<#
.SYNOPSIS
    Writes a section header to the console and log file.
.PARAMETER Title
    The title of the section.
#>
function Write-Section {
    param([string]$Title)
    Write-Host "`n   [$Title]" -ForegroundColor $ColorHeader
    Write-Host "   " ("-" * ($Title.Length + 2)) -ForegroundColor $ColorAccent
    if ($LogFilePath) {
        Add-Content -Path $LogFilePath -Value "`n[$Title]" -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Writes a log message to the console and log file.
.PARAMETER Status
    The status tag (e.g., INFO, ERROR, SUCCESS).
.PARAMETER Message
    The message to log.
.PARAMETER Color
    The color of the status tag in the console.
#>
function Write-AutoDerivaLog {
    param(
        [string]$Status,
        [string]$Message,
        [string]$Color = "White"
    )

    # Log Levels
    $Levels = @{
        "DEBUG" = 1
        "INFO"  = 2
        "WARN"  = 3
        "ERROR" = 4
        "FATAL" = 5
    }

    # Map Status to Level
    $CurrentLevel = "INFO"
    switch ($Status) {
        "DEBUG"   { $CurrentLevel = "DEBUG" }
        "WARN"    { $CurrentLevel = "WARN" }
        "ERROR"   { $CurrentLevel = "ERROR" }
        "FATAL"   { $CurrentLevel = "FATAL" }
        "SUCCESS" { $CurrentLevel = "INFO" }
        "PROCESS" { $CurrentLevel = "INFO" }
        "INSTALL" { $CurrentLevel = "INFO" }
        "START"   { $CurrentLevel = "INFO" }
        "DONE"    { $CurrentLevel = "INFO" }
        default   { $CurrentLevel = "INFO" }
    }

    $ConfigLevel = "INFO"
    if ($Config.LogLevel) { $ConfigLevel = $Config.LogLevel }
    
    $ConfigLevelVal = $Levels[$ConfigLevel.ToUpper()]
    if (-not $ConfigLevelVal) { $ConfigLevelVal = 2 }

    $MsgLevelVal = $Levels[$CurrentLevel]
    
    # Filter
    if ($MsgLevelVal -ge $ConfigLevelVal) {
        # Console Output
        Write-Host "   [" -NoNewline -ForegroundColor $ColorDim
        Write-Host "$Status" -NoNewline -ForegroundColor $Color
        Write-Host "] $Message" -ForegroundColor $ColorText
        
        # File Output
        if ($LogFilePath) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            # Use standardized level for log file consistency
            Add-Content -Path $LogFilePath -Value "[$timestamp] [$CurrentLevel] $Message" -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# 3. HELPER FUNCTIONS
# ---------------------------------------------------------------------------

# Global cache for downloaded CSVs to avoid re-fetching
$Script:CsvCache = @{}

<#
.SYNOPSIS
    Downloads a file from a URL to a local path.
.PARAMETER Url
    The URL of the file to download.
.PARAMETER OutputPath
    The local path where the file should be saved.
.OUTPUTS
    Boolean. True if successful, False otherwise.
#>
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

<#
.SYNOPSIS
    Fetches a CSV file from a remote URL and parses it.
.PARAMETER Url
    The URL of the CSV file.
.OUTPUTS
    PSCustomObject[]. The parsed CSV data.
#>
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

<#
.SYNOPSIS
    Performs pre-flight checks before starting the installation.
.DESCRIPTION
    Checks for internet connectivity.
#>
function Test-PreFlight {
    Write-Section "Pre-flight Checks"
    
    # Check Internet Connection
    try {
        $testUrl = "https://github.com"
        $request = [System.Net.WebRequest]::Create($testUrl)
        $request.Timeout = 5000
        $response = $request.GetResponse()
        $response.Close()
        Write-AutoDerivaLog "INFO" "Internet connection verified." "Green"
    } catch {
        Write-AutoDerivaLog "WARN" "Internet connection check failed. Remote downloads may fail." "Yellow"
    }
}

<#
.SYNOPSIS
    Retrieves the Hardware IDs of the current system.
.OUTPUTS
    String[]. A list of Hardware IDs.
#>
function Get-SystemHardware {
    Write-Section "Hardware Detection"
    Write-AutoDerivaLog "INFO" "Scanning system devices..." "Cyan"
    try {
        $SystemDevices = Get-PnpDevice -PresentOnly -ErrorAction Stop
        if (-not $SystemDevices) { throw "Get-PnpDevice returned no results." }
    } catch {
        throw "Failed to query system devices: $_"
    }
    
    $SystemHardwareIds = $SystemDevices.HardwareID | Where-Object { $_ } | ForEach-Object { $_.ToUpper() }
    $Script:Stats.DriversScanned = $SystemHardwareIds.Count
    Write-AutoDerivaLog "INFO" "Found $( $SystemHardwareIds.Count ) active hardware IDs." "Green"
    return $SystemHardwareIds
}

<#
.SYNOPSIS
    Finds compatible drivers from the inventory based on system Hardware IDs.
.PARAMETER DriverInventory
    The driver inventory list.
.PARAMETER SystemHardwareIds
    The list of system Hardware IDs.
.OUTPUTS
    PSCustomObject[]. A list of compatible driver objects.
#>
function Find-CompatibleDriver {
    param($DriverInventory, $SystemHardwareIds)
    
    Write-Section "Driver Matching"
    $DriverMatches = @()
    
    foreach ($driver in $DriverInventory) {
        # Parse HWIDs from CSV (semicolon separated)
        $driverHwids = $driver.HardwareIDs -split ";"
        
        # Check for intersection
        $intersect = $driverHwids | Where-Object { $SystemHardwareIds -contains $_.ToUpper() }
        
        if ($intersect) {
            $DriverMatches += $driver
        }
    }
    $Script:Stats.DriversMatched = $DriverMatches.Count
    return $DriverMatches
}

<#
.SYNOPSIS
    Downloads and installs the matched drivers.
.PARAMETER DriverMatches
    The list of compatible drivers.
.PARAMETER TempDir
    The temporary directory to use for downloads.
#>
function Install-Driver {
    param($DriverMatches, $TempDir)
    
    if ($DriverMatches.Count -eq 0) {
        Write-AutoDerivaLog "INFO" "No compatible drivers found in the inventory." "Yellow"
        return
    }

    Write-AutoDerivaLog "SUCCESS" "Found $( $DriverMatches.Count ) compatible drivers." "Green"
    
    # Fetch File Manifest
    Write-Section "File Manifest & Download"
    $ManifestUrl = $Config.BaseUrl + $Config.ManifestPath
    $FileManifest = Get-RemoteCsv -Url $ManifestUrl
    
    # Group matches by INF path to avoid duplicate downloads
    $UniqueInfs = $DriverMatches | Select-Object -ExpandProperty InfPath -Unique
    $totalDrivers = $UniqueInfs.Count
    $currentDriverIndex = 0
    
    foreach ($infPath in $UniqueInfs) {
        $currentDriverIndex++
        $driverPercent = [math]::Min(100, [int](($currentDriverIndex / $totalDrivers) * 100))
        
        Write-Progress -Id 1 -Activity "Installing Drivers" -Status "Processing $infPath ($currentDriverIndex/$totalDrivers)" -PercentComplete $driverPercent

        Write-AutoDerivaLog "PROCESS" "Processing driver: $infPath" "Cyan"
        
        # Find all files associated with this INF in the manifest
        # Note: AssociatedInf in manifest uses forward slashes, ensure matching format
        $TargetInf = $infPath.Replace('\', '/')
        $DriverFiles = $FileManifest | Where-Object { $_.AssociatedInf -eq $TargetInf }
        
        if (-not $DriverFiles) {
            Write-AutoDerivaLog "WARN" "No files found in manifest for $infPath" "Yellow"
            continue
        }
        
        $totalFiles = $DriverFiles.Count
        $currentFileIndex = 0

        foreach ($file in $DriverFiles) {
            $currentFileIndex++
            $fileName = Split-Path $file.RelativePath -Leaf
            $percentComplete = [math]::Min(100, [int](($currentFileIndex / $totalFiles) * 100))
            
            Write-Progress -Id 2 -ParentId 1 -Activity "Downloading Files" -Status "$fileName" -PercentComplete $percentComplete

            $remoteUrl = $Config.BaseUrl + $file.RelativePath
            # Reconstruct path in TempDir
            $localPath = Join-Path $TempDir $file.RelativePath.Replace('/', '\')
            
            Invoke-DownloadFile -Url $remoteUrl -OutputPath $localPath
            $Script:Stats.FilesDownloaded++
        }
        Write-Progress -Id 2 -Completed
        
        # Install Driver
        # The INF file is at $TempDir + $infPath
        $LocalInfPath = Join-Path $TempDir $infPath.Replace('/', '\')
        
        if (Test-Path $LocalInfPath) {
            Write-AutoDerivaLog "INSTALL" "Installing driver..." "Cyan"
            $proc = Start-Process -FilePath "pnputil.exe" -ArgumentList "/add-driver `"$LocalInfPath`" /install" -NoNewWindow -Wait -PassThru
            
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) { # 3010 = Reboot required
                Write-AutoDerivaLog "SUCCESS" "Driver installed successfully." "Green"
                $Script:Stats.DriversInstalled++
                if ($proc.ExitCode -eq 3010) { $Script:Stats.RebootsRequired++ }
            } else {
                Write-AutoDerivaLog "ERROR" "Driver installation failed. Exit Code: $($proc.ExitCode)" "Red"
                $Script:Stats.DriversFailed++
            }
        } else {
            Write-AutoDerivaLog "ERROR" "INF file not found after download: $LocalInfPath" "Red"
        }
    }
    Write-Progress -Id 1 -Completed
}

<#
.SYNOPSIS
    Downloads the Cuco binary to the Desktop.
#>
function Install-Cuco {
    Write-Section "Cuco Utility"
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $CucoDest = Join-Path $DesktopPath "CtoolGui.exe"
    $CucoUrl = $Config.BaseUrl + $Config.CucoBinaryPath

    Write-AutoDerivaLog "INFO" "Downloading Cuco utility to Desktop..." "Cyan"
    
    try {
        Invoke-DownloadFile -Url $CucoUrl -OutputPath $CucoDest
        if (Test-Path $CucoDest) {
            Write-AutoDerivaLog "SUCCESS" "Cuco utility downloaded to: $CucoDest" "Green"
        } else {
            Write-AutoDerivaLog "ERROR" "Failed to verify Cuco download." "Red"
        }
    } catch {
        Write-AutoDerivaLog "ERROR" "Failed to download Cuco: $_" "Red"
    }
}

<#
.SYNOPSIS
    Downloads all files from the manifest to the temp directory.
#>
function Invoke-DownloadAllFile {
    param($TempDir)
    
    Write-Section "Download All Files"
    Write-AutoDerivaLog "INFO" "DownloadAllFiles is enabled. Fetching all files..." "Cyan"
    
    $ManifestUrl = $Config.BaseUrl + $Config.ManifestPath
    $FileManifest = Get-RemoteCsv -Url $ManifestUrl
    
    $totalFiles = $FileManifest.Count
    $currentFileIndex = 0
    
    foreach ($file in $FileManifest) {
        $currentFileIndex++
        $fileName = Split-Path $file.RelativePath -Leaf
        $percentComplete = [math]::Min(100, [int](($currentFileIndex / $totalFiles) * 100))
        
        Write-Progress -Activity "Downloading All Files" -Status "Downloading $fileName ($currentFileIndex/$totalFiles)" -PercentComplete $percentComplete
        
        $remoteUrl = $Config.BaseUrl + $file.RelativePath
        $localPath = Join-Path $TempDir $file.RelativePath.Replace('/', '\')
        
        Invoke-DownloadFile -Url $remoteUrl -OutputPath $localPath
        $Script:Stats.FilesDownloaded++
    }
    Write-Progress -Activity "Downloading All Files" -Completed
    Write-AutoDerivaLog "SUCCESS" "All files downloaded to $TempDir" "Green"
}

<#
.SYNOPSIS
    Main execution function.
#>
function Main {
    try {
        Write-BrandHeader
        Write-AutoDerivaLog "START" "AutoDeriva Installer Initialized" "Green"
        
        Test-PreFlight

        # Install Cuco
        Install-Cuco

        # Create Temp Directory
        $TempDir = Join-Path $env:TEMP "AutoDeriva_$(Get-Random)"
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
        Write-AutoDerivaLog "INFO" "Temporary workspace: $TempDir" "Gray"

        # Download All Files if configured
        if ($Config.DownloadAllFiles) {
            Invoke-DownloadAllFile -TempDir $TempDir
        }

        # Get Hardware IDs
        $SystemHardwareIds = Get-SystemHardware

        # Fetch Driver Inventory
        Write-Section "Driver Inventory"
        $InventoryUrl = $Config.BaseUrl + $Config.InventoryPath
        $DriverInventory = Get-RemoteCsv -Url $InventoryUrl
        Write-AutoDerivaLog "INFO" "Loaded $( $DriverInventory.Count ) drivers from remote inventory." "Green"

        # Match Drivers
        $DriverMatches = Find-CompatibleDriver -DriverInventory $DriverInventory -SystemHardwareIds $SystemHardwareIds

        # Install Drivers
        Install-Driver -DriverMatches $DriverMatches -TempDir $TempDir

        # Cleanup
        Write-Section "Cleanup"
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force
            Write-AutoDerivaLog "INFO" "Temporary files removed." "Green"
        }

        Write-Section "Completion"
        $Duration = New-TimeSpan -Start $Script:Stats.StartTime -End (Get-Date)
        Write-AutoDerivaLog "DONE" "AutoDeriva process completed in $($Duration.ToString('hh\:mm\:ss'))." "Green"
        
        Write-Section "Statistics"
        Write-AutoDerivaLog "INFO" "Hardware IDs Scanned : $($Script:Stats.DriversScanned)" "Cyan"
        Write-AutoDerivaLog "INFO" "Drivers Matched      : $($Script:Stats.DriversMatched)" "Cyan"
        Write-AutoDerivaLog "INFO" "Files Downloaded     : $($Script:Stats.FilesDownloaded)" "Cyan"
        Write-AutoDerivaLog "INFO" "Drivers Installed    : $($Script:Stats.DriversInstalled)" "Green"
        Write-AutoDerivaLog "INFO" "Drivers Failed       : $($Script:Stats.DriversFailed)" "Red"
        if ($Script:Stats.RebootsRequired -gt 0) {
            Write-AutoDerivaLog "WARN" "Reboots Required     : $($Script:Stats.RebootsRequired)" "Yellow"
        }

        if ($LogFilePath) {
            Write-AutoDerivaLog "INFO" "Log saved to: $LogFilePath" "Gray"
        }

    } catch {
        Write-AutoDerivaLog "FATAL" "An unexpected error occurred: $_" "Red"
        Write-AutoDerivaLog "FATAL" $($_.ScriptStackTrace) "Red"
    } finally {
        Write-Host "`n"
        Read-Host "Press Enter to close this window..."
    }
}

# ---------------------------------------------------------------------------
# 4. EXECUTION
# ---------------------------------------------------------------------------

Main
