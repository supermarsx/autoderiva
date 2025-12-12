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
$ConfigDefaultsFile = Join-Path $Script:RepoRoot "config.defaults.json"
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
    MaxRetries = 5
    MaxBackoffSeconds = 60
    MinDiskSpaceMB = 3072
}

# Initialize Config with Hardcoded Defaults
$Config = $DefaultConfig.Clone()

# 1. Load config.defaults.json (Local or Remote)
if (Test-Path $ConfigDefaultsFile) {
    Write-Host "Loading default configuration from $ConfigDefaultsFile..." -ForegroundColor Cyan
    try {
        $FileConfig = Get-Content $ConfigDefaultsFile | ConvertFrom-Json
        foreach ($prop in $FileConfig.PSObject.Properties) {
            $Config[$prop.Name] = $prop.Value
        }
    } catch {
        Write-Warning "Failed to parse local defaults. Using internal defaults."
    }
} else {
    # Try to fetch remote defaults
    $RemoteConfigUrl = "https://raw.githubusercontent.com/supermarsx/autoderiva/main/config.defaults.json"
    Write-Host "Local defaults not found. Attempting to fetch remote defaults from $RemoteConfigUrl..." -ForegroundColor Cyan
    try {
        $RemoteConfigJson = Invoke-WebRequest -Uri $RemoteConfigUrl -UseBasicParsing -ErrorAction Stop
        $RemoteConfig = $RemoteConfigJson.Content | ConvertFrom-Json
        
        foreach ($prop in $RemoteConfig.PSObject.Properties) {
            $Config[$prop.Name] = $prop.Value
        }
        Write-Host "Successfully loaded remote defaults." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to fetch remote defaults. Using internal defaults."
    }
}

# 2. Load config.json (Local Override)
if (Test-Path $ConfigFile) {
    Write-Host "Loading local overrides from $ConfigFile..." -ForegroundColor Cyan
    try {
        $LocalConfig = Get-Content $ConfigFile | ConvertFrom-Json
        foreach ($prop in $LocalConfig.PSObject.Properties) {
            $Config[$prop.Name] = $prop.Value
        }
    } catch {
        Write-Warning "Failed to parse local overrides."
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
$Script:ColorHeader = "Cyan"
$Script:ColorText = "White"
$Script:ColorAccent = "Blue"
$Script:ColorDim = "Gray"

<#
.SYNOPSIS
    Displays the AutoDeriva brand header.
.DESCRIPTION
    Clears the host and prints the ASCII art logo and title.
#>
function Write-BrandHeader {
    # Set Background Color
    try {
        $Host.UI.RawUI.BackgroundColor = "Black"
    } catch {
        Write-Verbose "Could not set background color."
    }
    Clear-Host
    
    $Art = @(
        ' *        .        ★        .        *        .',
        '   .        ★          .        *        .        ★',
        '        ★        .        *        .        ★        .',
        '   .        *        .        ★        .        *        .',
        '',
        '             ´ | ` ',
        '      ________ |________',
        '     \__________________/',
        '',
        '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
        '   ~~~~~~\____/~~~~\____/~~~~\____/~~~~\____/~~~~~~',
        ' ~~~~~\____/~~~~\____/~~~~\____/~~~~\____/~~~~\____/~~~~'
    )
    
    $Rainbow = @('Red', 'DarkYellow', 'Yellow', 'Green', 'Magenta', 'DarkMagenta')
    $SeaColors = @('Cyan', 'DarkCyan', 'Blue', 'DarkBlue')
    
    for ($i = 0; $i -lt $Art.Count; $i++) {
        if ($i -ge 9) {
            $Color = $SeaColors[$i % $SeaColors.Count]
        } else {
            $Color = $Rainbow[$i % $Rainbow.Count]
        }
        Write-Host $Art[$i] -ForegroundColor $Color
    }
    
    Write-Host "   System Setup & Driver Installer" -ForegroundColor $Script:ColorDim
    Write-Host "   " ("=" * 60) -ForegroundColor $Script:ColorAccent
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
    Write-Host "`n   [$Title]" -ForegroundColor $Script:ColorHeader
    Write-Host "   " ("-" * ($Title.Length + 2)) -ForegroundColor $Script:ColorAccent
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
        Write-Host "   [" -NoNewline -ForegroundColor $Script:ColorDim
        Write-Host "$Status" -NoNewline -ForegroundColor $Color
        Write-Host "] $Message" -ForegroundColor $Script:ColorText
        
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
    Formats a byte count into a human-readable string.
.PARAMETER Bytes
    The number of bytes.
#>
function Format-FileSize {
    param([long]$Bytes)
    $sizes = @("B", "KB", "MB", "GB", "TB")
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt $sizes.Count - 1) {
        $Bytes /= 1024
        $i++
    }
    return "{0:N2} {1}" -f $Bytes, $sizes[$i]
}

<#
.SYNOPSIS
    Downloads a file from a URL to a local path with retry logic and exponential backoff.
.PARAMETER Url
    The URL of the file to download.
.PARAMETER OutputPath
    The local path where the file should be saved.
.PARAMETER MaxRetries
    Number of times to retry the download.
.OUTPUTS
    Boolean. True if successful, False otherwise.
#>
function Invoke-DownloadFile {
    param($Url, $OutputPath, $MaxRetries = $Config.MaxRetries)
    try {
        $dir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        
        $retryCount = 0
        $success = $false
        $backoff = 2 # Start with 2 seconds
        
        while (-not $success -and $retryCount -lt $MaxRetries) {
            try {
                Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
                $success = $true
            } catch {
                $retryCount++
                Write-AutoDerivaLog "WARN" "Download failed (Attempt $retryCount/$MaxRetries): $Url" "Yellow"
                if ($retryCount -lt $MaxRetries) { 
                    Write-AutoDerivaLog "INFO" "Retrying in $backoff seconds..." "Gray"
                    Start-Sleep -Seconds $backoff
                    
                    # Exponential Backoff with Cap
                    $backoff = [math]::Min($backoff * 2, $Config.MaxBackoffSeconds)
                }
            }
        }
        
        if (-not $success) {
            throw "Failed to download after $MaxRetries attempts."
        }
        
        return $true
    }
    catch {
        Write-AutoDerivaLog "ERROR" "Failed to download: $Url. Error: $_" "Red"
        return $false
    }
}

<#
.SYNOPSIS
    Checks if there is enough free disk space on the drive.
.PARAMETER Path
    The path to check.
.PARAMETER MinMB
    Minimum required space in Megabytes.
.OUTPUTS
    Boolean.
#>
function Test-DiskSpace {
    param($Path, $MinMB = $Config.MinDiskSpaceMB)
    try {
        $drive = Get-PSDrive -Name (Split-Path $Path -Qualifier).TrimEnd(':') -ErrorAction Stop
        $freeMB = [math]::Round($drive.Free / 1MB, 2)
        
        $freeReadable = Format-FileSize ($drive.Free)
        $reqReadable = Format-FileSize ($MinMB * 1MB)

        if ($freeMB -lt $MinMB) {
            Write-AutoDerivaLog "ERROR" "Insufficient disk space on $($drive.Name). Free: $freeReadable, Required: $reqReadable" "Red"
            return $false
        }
        Write-AutoDerivaLog "INFO" "Disk space check passed. Free: $freeReadable" "Green"
        return $true
    } catch {
        Write-AutoDerivaLog "WARN" "Could not verify disk space: $_" "Yellow"
        return $true # Assume true on error to avoid blocking
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
.OUTPUTS
    PSCustomObject[]. List of installation results.
#>
function Install-Driver {
    param($DriverMatches, $TempDir)
    
    $Results = @()

    if ($DriverMatches.Count -eq 0) {
        Write-AutoDerivaLog "INFO" "No compatible drivers found in the inventory." "Yellow"
        return $Results
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
            $Results += [PSCustomObject]@{ Driver = $infPath; Status = "Skipped (No Files)"; Details = "Manifest missing files" }
            continue
        }
        
        $totalFiles = $DriverFiles.Count
        $currentFileIndex = 0
        $downloadFailed = $false

        foreach ($file in $DriverFiles) {
            $currentFileIndex++
            $fileName = Split-Path $file.RelativePath -Leaf
            $percentComplete = [math]::Min(100, [int](($currentFileIndex / $totalFiles) * 100))
            
            $sizeStr = ""
            if ($file.Size) {
                $sizeStr = " (" + (Format-FileSize $file.Size) + ")"
            }

            Write-Progress -Id 2 -ParentId 1 -Activity "Downloading Files" -Status "$fileName$sizeStr" -PercentComplete $percentComplete

            $remoteUrl = $Config.BaseUrl + $file.RelativePath
            # Reconstruct path in TempDir
            $localPath = Join-Path $TempDir $file.RelativePath.Replace('/', '\')
            
            $dlResult = Invoke-DownloadFile -Url $remoteUrl -OutputPath $localPath
            if ($dlResult) {
                $Script:Stats.FilesDownloaded++
            } else {
                $downloadFailed = $true
                break
            }
        }
        Write-Progress -Id 2 -Completed
        
        if ($downloadFailed) {
            Write-AutoDerivaLog "ERROR" "Aborting installation for $infPath due to download failure." "Red"
            $Results += [PSCustomObject]@{ Driver = $infPath; Status = "Failed"; Details = "Download Error" }
            $Script:Stats.DriversFailed++
            continue
        }

        # Install Driver
        # The INF file is at $TempDir + $infPath
        $LocalInfPath = Join-Path $TempDir $infPath.Replace('/', '\')
        
        if (Test-Path $LocalInfPath) {
            Write-AutoDerivaLog "INSTALL" "Installing driver..." "Cyan"
            $proc = Start-Process -FilePath "pnputil.exe" -ArgumentList "/add-driver `"$LocalInfPath`" /install" -NoNewWindow -Wait -PassThru
            
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) { # 3010 = Reboot required
                Write-AutoDerivaLog "SUCCESS" "Driver installed successfully." "Green"
                $Script:Stats.DriversInstalled++
                $status = "Installed"
                if ($proc.ExitCode -eq 3010) { 
                    $Script:Stats.RebootsRequired++ 
                    $status = "Installed (Reboot Req)"
                }
                $Results += [PSCustomObject]@{ Driver = $infPath; Status = $status; Details = "Success" }
            } else {
                Write-AutoDerivaLog "ERROR" "Driver installation failed. Exit Code: $($proc.ExitCode)" "Red"
                $Script:Stats.DriversFailed++
                $Results += [PSCustomObject]@{ Driver = $infPath; Status = "Failed"; Details = "PnPUtil Exit Code $($proc.ExitCode)" }
            }
        } else {
            Write-AutoDerivaLog "ERROR" "INF file not found after download: $LocalInfPath" "Red"
            $Results += [PSCustomObject]@{ Driver = $infPath; Status = "Failed"; Details = "INF Missing" }
        }
    }
    Write-Progress -Id 1 -Completed
    return $Results
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
        
        $sizeStr = ""
        if ($file.Size) {
            $sizeStr = " (" + (Format-FileSize $file.Size) + ")"
        }

        Write-Progress -Activity "Downloading All Files" -Status "Downloading $fileName$sizeStr ($currentFileIndex/$totalFiles)" -PercentComplete $percentComplete
        
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

        # Check Disk Space
        if (-not (Test-DiskSpace -Path $TempDir)) {
            Write-AutoDerivaLog "FATAL" "Not enough disk space to proceed." "Red"
            return
        }

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
        $InstallResults = Install-Driver -DriverMatches $DriverMatches -TempDir $TempDir

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

        if ($InstallResults.Count -gt 0) {
            Write-Section "Detailed Summary"
            $InstallResults | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White
            if ($LogFilePath) {
                $InstallResults | Format-Table -AutoSize | Out-String | Add-Content -Path $LogFilePath
            }
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


