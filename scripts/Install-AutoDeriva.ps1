# .SYNOPSIS
#     AutoDeriva System Setup "&" Driver Installer (Remote/Hybrid Mode)
#    
# .DESCRIPTION
#     This script performs the following actions:
#     1. Loads configuration from config.json.
#     2. Downloads the driver inventory from the remote repository.
#     3. Scans the local system for Hardware IDs.
#     4. Matches system devices against the remote driver inventory.
#     5. If matches are found:
#        - Downloads the file manifest.
#        - Downloads all required files for the matched drivers to a temporary directory.
#        - Reconstructs the folder structure.
#        - Installs drivers using PnPUtil.
#     6. Cleans up temporary files.
#    
#     Features:
#     - Auto-elevation (Runs as Administrator)
#     - TUI with color-coded output
#     - Smart driver matching based on Hardware IDs
#     - Remote file fetching (no local drivers folder required)
#     - Detailed logging to file and console
#     - In-memory caching of inventory and manifest to prevent redundant downloads
#
# .EXAMPLE
#     Run from PowerShell:
#     .\Install-AutoDeriva.ps1

# ---------------------------------------------------------------------------
# Script CLI Parameters
# ---------------------------------------------------------------------------
param(
    [string]$ConfigPath,
    [string]$ConfigUrl,
    [switch]$EnableLogging,
    [switch]$CleanLogs,
    [int]$LogRetentionDays,
    [int]$MaxLogFiles,
    [switch]$NoLogCleanup,
    [switch]$DownloadAllFiles,
    [Alias('DownloadOnly')][switch]$DownloadAllAndExit,
    [switch]$DownloadCuco,
    [Alias('CucoOnly')][switch]$DownloadCucoAndExit,
    [string]$CucoTargetDir,
    [switch]$AskBeforeDownloadCuco,
    [switch]$NoAskBeforeDownloadCuco,
    [switch]$SingleDownloadMode,
    [int]$MaxConcurrentDownloads,
    [switch]$NoDiskSpaceCheck,

    # File integrity verification
    [bool]$VerifyFileHashes,
    [bool]$DeleteFilesOnHashMismatch,
    [ValidateSet('Continue', 'SkipDriver', 'Abort')][string]$HashMismatchPolicy,
    [ValidateSet('Parallel', 'Single')][string]$HashVerifyMode,
    [int]$HashVerifyMaxConcurrency,

    # Driver scan behavior
    [switch]$ScanOnlyMissingDrivers,
    [switch]$ScanAllDevices,

    # Export helpers
    [string]$ExportUnknownDevicesCsv,

    # Wi-Fi cleanup behavior
    [Alias('WifiCleanupAndExit', 'WifiOnly')][switch]$ClearWifiAndExit,
    [switch]$ClearWifiProfiles,
    [Alias('NoClearWifiProfiles')][switch]$NoWifiCleanup,
    # WifiCleanupMode: SingleOnly (delete only WifiProfileNameToDelete), All, or None.
    [ValidateSet('SingleOnly', 'All', 'None')][string]$WifiCleanupMode,
    [Alias('WifiName', 'WifiProfileName')][string]$WifiProfileNameToDelete,
    [switch]$AskBeforeClearingWifiProfiles,
    [switch]$NoAskBeforeClearingWifiProfiles,

    # End-of-run behavior
    [switch]$AutoExitWithoutConfirmation,
    [switch]$RequireExitConfirmation,

    # Banner / UI
    [bool]$ShowBanner,

    # Performance tweaks (default enabled via config)
    [switch]$NoDisableOneDriveStartup,
    [switch]$NoHideTaskViewButton,
    [switch]$NoDisableNewsAndInterestsAndWidgets,
    [switch]$NoHideTaskbarSearch,

    # Performance tuning
    [ValidateSet('Parallel', 'Single')][string]$DeviceScanMode,
    [int]$DeviceScanMaxConcurrency,

    # Stats display
    [switch]$ShowOnlyNonZeroStats,
    [switch]$ShowAllStats,

    [switch]$ShowConfig,
    [switch]$DryRun,
    [Alias('?')][switch]$Help
)

# ---------------------------------------------------------------------------
# 1. AUTO-ELEVATION
# ---------------------------------------------------------------------------
# During automated tests, setting the AUTODERIVA_TEST env var to '1' will skip
# the auto-elevation behavior so tests can run non-interactively.
if ($env:AUTODERIVA_TEST -ne '1') {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "Requesting administrative privileges..." -ForegroundColor Yellow
        $noExit = ($env:AUTODERIVA_NOEXIT -eq '1')
        $elevatedArgList = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
        if ($noExit) { $elevatedArgList += '-NoExit' }

        # If launched via the BAT, prefer the repo-local script path for elevation.
        # This avoids a race where the BAT deletes the temp-downloaded script while
        # the elevated process is starting.
        $scriptToRun = $MyInvocation.MyCommand.Definition
        try {
            if ($env:AUTODERIVA_REPOROOT) {
                $candidate = Join-Path $env:AUTODERIVA_REPOROOT 'scripts\Install-AutoDeriva.ps1'
                if (Test-Path -LiteralPath $candidate) { $scriptToRun = $candidate }
            }
        }
        catch {
            Write-Verbose "Failed to resolve repo script path for elevation: $_"
        }

        # If we're still pointing at a temp-downloaded script, copy it to a stable
        # temp location so the BAT launcher can't delete it before the elevated
        # process reads it.
        try {
            $tempRoot = $env:TEMP
            if ($tempRoot -and $scriptToRun -and (Test-Path -LiteralPath $scriptToRun)) {
                $full = (Resolve-Path -LiteralPath $scriptToRun).Path
                if ($full -like (Join-Path $tempRoot '*')) {
                    $stableDir = Join-Path $tempRoot 'AutoDeriva_Elevate'
                    if (-not (Test-Path -LiteralPath $stableDir)) {
                        New-Item -ItemType Directory -Path $stableDir -Force | Out-Null
                    }
                    $stable = Join-Path $stableDir 'Install-AutoDeriva.ps1'
                    Copy-Item -LiteralPath $full -Destination $stable -Force
                    $scriptToRun = $stable
                }
            }
        }
        catch {
            Write-Verbose "Failed to create stable elevation script copy: $_"
        }

        $elevatedArgList += @('-File', $scriptToRun)

        # Preserve original CLI args for the elevated run.
        # Prefer $PSBoundParameters (typed) so switches/values are reconstructed reliably.
        foreach ($key in $PSBoundParameters.Keys) {
            $value = $PSBoundParameters[$key]
            if ($value -is [switch]) {
                if ($value.IsPresent) { $elevatedArgList += "-$key" }
                continue
            }
            if ($null -eq $value) {
                continue
            }
            if ($value -is [bool]) {
                $elevatedArgList += @("-$key", ([string]$value).ToLowerInvariant())
                continue
            }
            $elevatedArgList += @("-$key", [string]$value)
        }

        # Use the current host executable when possible (pwsh stays pwsh; Windows PowerShell stays powershell).
        $hostExe = 'powershell.exe'
        try {
            $pwshInPSHome = Join-Path $PSHOME 'pwsh.exe'
            $powershellInPSHome = Join-Path $PSHOME 'powershell.exe'
            if (Test-Path -LiteralPath $pwshInPSHome) { $hostExe = $pwshInPSHome }
            elseif (Test-Path -LiteralPath $powershellInPSHome) { $hostExe = $powershellInPSHome }
        }
        catch {
            Write-Verbose "Failed to resolve host exe from PSHOME: $_"
        }

        $wd = $null
        try {
            if ($env:AUTODERIVA_REPOROOT -and (Test-Path -LiteralPath $env:AUTODERIVA_REPOROOT)) { $wd = $env:AUTODERIVA_REPOROOT }
        }
        catch { $wd = $null }

        if ($wd) {
            Start-Process -FilePath $hostExe -ArgumentList $elevatedArgList -WorkingDirectory $wd -Verb RunAs -PassThru | Out-Null
        }
        else {
            Start-Process -FilePath $hostExe -ArgumentList $elevatedArgList -Verb RunAs -PassThru | Out-Null
        }

        # IMPORTANT: `exit` terminates the entire host (even if launched with -NoExit).
        # When troubleshooting mode is enabled, return so the console remains open.
        if ($noExit) { return }
        exit
    }
}
else {
    Write-Verbose "AUTODERIVA_TEST set - skipping auto-elevation for test environment."
}

# Set Console Colors / clear screen (skip during tests to avoid VS Code hangs/flaky terminal behavior)
if ($env:AUTODERIVA_TEST -ne '1') {
    try {
        $Host.UI.RawUI.BackgroundColor = "DarkBlue"
        $Host.UI.RawUI.ForegroundColor = "White"
        Clear-Host
    }
    catch {
        # Non-fatal: some hosts (VS Code, non-interactive) may not allow RawUI operations.
        Write-Verbose "RawUI/Clear-Host not supported in this host: $_"
    }
}

# Ensure TLS 1.2 is enabled for web requests (Crucial for GitHub and modern APIs on older PS/Windows)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ErrorActionPreference = "Stop"
$Script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$ConfigDefaultsFile = Join-Path $Script:RepoRoot "config.defaults.json"
$ConfigFile = Join-Path $Script:RepoRoot "config.json"

function Write-AutoDerivaBanner {
    try {
        $width = 0
        try {
            if ($Host -and $Host.UI -and $Host.UI.RawUI) {
                # WindowSize can throw in some hosts; BufferSize is sometimes more stable.
                try { $width = [int]$Host.UI.RawUI.WindowSize.Width } catch { $width = 0 }
                if ($width -le 0) {
                    try { $width = [int]$Host.UI.RawUI.BufferSize.Width } catch { $width = 0 }
                }
            }
        }
        catch { $width = 0 }

        # Keep banner lines within the current width to prevent wrapping/reflow.
        # Use a sensible maximum so the banner stays compact.
        $maxBannerWidth = 60
        if ($width -le 0) { $width = $maxBannerWidth + 1 }
        $lineWidth = [Math]::Min([Math]::Max(($width - 1), 10), $maxBannerWidth)

        $rule = ('=' * $lineWidth)

        $title = 'AutoDeriva - System Setup & Driver Tool'
        if ($title.Length -gt ($lineWidth - 2)) {
            # Truncate and add ellipsis when the console is narrow.
            $maxTitle = [Math]::Max(($lineWidth - 5), 8)
            if ($title.Length -gt $maxTitle) { $title = $title.Substring(0, $maxTitle) + '...' }
        }

        # Center the title within the rule width.
        $padTotal = [Math]::Max(($lineWidth - $title.Length), 0)
        $padLeft = [Math]::Floor($padTotal / 2)
        $padRight = $padTotal - $padLeft
        $titleLine = (' ' * $padLeft) + $title + (' ' * $padRight)

        Write-Host ''
        Write-Host $rule -ForegroundColor Cyan
        Write-Host $titleLine -ForegroundColor Cyan
        Write-Host $rule -ForegroundColor Cyan
        Write-Host ''
    }
    catch {
        Write-Verbose "Failed to print banner: $_"
    }
}

function Get-AutoDerivaInteractiveUserSid {
    [CmdletBinding()]
    param()

    if ($Script:Test_GetInteractiveUserSid) {
        return & $Script:Test_GetInteractiveUserSid
    }

    try {
        $explorerProc = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($explorerProc -and $explorerProc.UserName) {
            $acct = New-Object System.Security.Principal.NTAccount($explorerProc.UserName)
            $sid = $acct.Translate([System.Security.Principal.SecurityIdentifier])
            if ($sid -and $sid.Value) { return [string]$sid.Value }
        }
    }
    catch {
        Write-Verbose "Failed to resolve interactive user SID via explorer.exe owner: $_"
    }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs -and $cs.UserName) {
            $acct = New-Object System.Security.Principal.NTAccount([string]$cs.UserName)
            $sid = $acct.Translate([System.Security.Principal.SecurityIdentifier])
            if ($sid -and $sid.Value) { return [string]$sid.Value }
        }
    }
    catch {
        Write-Verbose "Failed to resolve interactive user SID via Win32_ComputerSystem: $_"
    }

    return $null
}

function Convert-AutoDerivaRegistryPathToInteractiveUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not $Path.StartsWith('HKCU:\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path
    }

    if ($env:AUTODERIVA_TEST -eq '1') {
        return $Path
    }

    $isAdmin = $false
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
    }
    catch {
        $isAdmin = $false
    }
    if (-not $isAdmin) {
        return $Path
    }

    $currentSid = $null
    try { $currentSid = [string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) } catch { $currentSid = $null }

    $interactiveSid = Get-AutoDerivaInteractiveUserSid
    if ([string]::IsNullOrWhiteSpace($interactiveSid)) {
        return $Path
    }

    if ($currentSid -and ($interactiveSid -eq $currentSid)) {
        return $Path
    }

    if (-not $Script:HkcuRedirectLogged) {
        $Script:HkcuRedirectLogged = $true
        Write-AutoDerivaLog 'INFO' ("Applying HKCU tweaks to interactive user hive (SID: {0})" -f $interactiveSid) 'Gray'
    }

    $subKey = $Path.Substring(6) # after 'HKCU:\'
    return ("Registry::HKEY_USERS\\{0}\\{1}" -f $interactiveSid, $subKey)
}

function Set-AutoDerivaRegistryDword {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    $effectivePath = Convert-AutoDerivaRegistryPathToInteractiveUser -Path $Path

    if ($PSCmdlet -and (-not $PSCmdlet.ShouldProcess("$effectivePath\\$Name", "Set DWORD to $Value"))) { return }

    if ($Script:DryRun) {
        Write-AutoDerivaLog 'INFO' "DryRun: Would set registry DWORD $effectivePath\\$Name=$Value" 'Gray'
        return
    }

    if ($Script:Test_SetRegistryDword) {
        try {
            & $Script:Test_SetRegistryDword -Path $effectivePath -Name $Name -Value $Value
        }
        catch [System.UnauthorizedAccessException] {
            Write-AutoDerivaLog 'WARN' "Insufficient permissions to set registry DWORD $effectivePath\\$Name=$Value. Skipping. Error: $($_.Exception.Message)" 'Yellow'
        }
        catch [System.Security.SecurityException] {
            Write-AutoDerivaLog 'WARN' "Insufficient permissions to set registry DWORD $effectivePath\\$Name=$Value. Skipping. Error: $($_.Exception.Message)" 'Yellow'
        }
        return
    }

    if (-not (Test-Path -LiteralPath $effectivePath)) {
        try {
            New-Item -Path $effectivePath -Force -ErrorAction Stop | Out-Null
        }
        catch [System.UnauthorizedAccessException] {
            Write-AutoDerivaLog 'WARN' "Insufficient permissions to create registry key $effectivePath. Skipping $Name=$Value. Error: $($_.Exception.Message)" 'Yellow'
            return
        }
        catch [System.Security.SecurityException] {
            Write-AutoDerivaLog 'WARN' "Insufficient permissions to create registry key $effectivePath. Skipping $Name=$Value. Error: $($_.Exception.Message)" 'Yellow'
            return
        }
        catch {
            Write-Verbose "Failed to create registry key ${effectivePath}: $_"
            return
        }
    }

    try {
        Set-ItemProperty -Path $effectivePath -Name $Name -Type DWord -Value $Value -Force -ErrorAction Stop | Out-Null
    }
    catch [System.UnauthorizedAccessException] {
        Write-AutoDerivaLog 'WARN' "Insufficient permissions to set registry DWORD $effectivePath\\$Name=$Value. Skipping. Error: $($_.Exception.Message)" 'Yellow'
    }
    catch [System.Security.SecurityException] {
        Write-AutoDerivaLog 'WARN' "Insufficient permissions to set registry DWORD $effectivePath\\$Name=$Value. Skipping. Error: $($_.Exception.Message)" 'Yellow'
    }
}

function Remove-AutoDerivaRegistryValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $effectivePath = Convert-AutoDerivaRegistryPathToInteractiveUser -Path $Path

    if ($PSCmdlet -and (-not $PSCmdlet.ShouldProcess("$effectivePath\\$Name", 'Remove registry value'))) { return }

    if ($Script:DryRun) {
        Write-AutoDerivaLog 'INFO' "DryRun: Would remove registry value $effectivePath\\$Name" 'Gray'
        return
    }

    if ($Script:Test_RemoveRegistryValue) {
        & $Script:Test_RemoveRegistryValue -Path $effectivePath -Name $Name
        return
    }

    try {
        Remove-ItemProperty -Path $effectivePath -Name $Name -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "Failed to remove registry value ${effectivePath}\\${Name}: $_"
    }
}

function Invoke-PerformanceTuning {
    [CmdletBinding()]
    param()

    Write-Section 'Performance Tweaks'

    $disableOneDriveStartup = $true
    $hideTaskView = $true
    $disableFeedsWidgets = $true
    $hideTaskbarSearch = $true

    try { $disableOneDriveStartup = [bool]$Config.DisableOneDriveStartup } catch { Write-Verbose "Failed to read DisableOneDriveStartup: $_" }
    try { $hideTaskView = [bool]$Config.HideTaskViewButton } catch { Write-Verbose "Failed to read HideTaskViewButton: $_" }
    try { $disableFeedsWidgets = [bool]$Config.DisableNewsAndInterestsAndWidgets } catch { Write-Verbose "Failed to read DisableNewsAndInterestsAndWidgets: $_" }
    try { $hideTaskbarSearch = [bool]$Config.HideTaskbarSearch } catch { Write-Verbose "Failed to read HideTaskbarSearch: $_" }

    if ($disableOneDriveStartup) {
        Write-AutoDerivaLog 'INFO' 'Disabling OneDrive auto-start...' 'Gray'
        Remove-AutoDerivaRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive'
        Remove-AutoDerivaRegistryValue -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive'
    }
    else {
        Write-AutoDerivaLog 'INFO' 'Skipping OneDrive auto-start tweak (disabled by config).' 'Gray'
    }

    if ($hideTaskView) {
        Write-AutoDerivaLog 'INFO' 'Hiding Task View button on taskbar...' 'Gray'
        Set-AutoDerivaRegistryDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowTaskViewButton' -Value 0
    }
    else {
        Write-AutoDerivaLog 'INFO' 'Skipping Task View tweak (disabled by config).' 'Gray'
    }

    if ($hideTaskbarSearch) {
        Write-AutoDerivaLog 'INFO' 'Hiding Search on taskbar...' 'Gray'
        Set-AutoDerivaRegistryDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 0
    }
    else {
        Write-AutoDerivaLog 'INFO' 'Skipping taskbar Search tweak (disabled by config).' 'Gray'
    }

    if ($disableFeedsWidgets) {
        Write-AutoDerivaLog 'INFO' 'Disabling News/Interests and Widgets...' 'Gray'

        # Windows 10: News and interests (Feeds)
        Set-AutoDerivaRegistryDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' -Name 'ShellFeedsTaskbarViewMode' -Value 2
        Set-AutoDerivaRegistryDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' -Name 'EnableFeeds' -Value 0

        # Windows 11: Widgets button
        Set-AutoDerivaRegistryDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Value 0
    }
    else {
        Write-AutoDerivaLog 'INFO' 'Skipping News/Interests & Widgets tweak (disabled by config).' 'Gray'
    }

    Write-AutoDerivaLog 'INFO' 'Performance tweaks applied (some changes may require Explorer restart or sign-out).' 'Gray'
}

# ---------------------------------------------------------------------------
# 2. CONFIGURATION & LOGGING
# ---------------------------------------------------------------------------

# Default Configuration (Fallback)
$DefaultConfig = @{
    BaseUrl                           = "https://raw.githubusercontent.com/supermarsx/autoderiva/main/"
    InventoryPath                     = "exports/driver_inventory.csv"
    ManifestPath                      = "exports/driver_file_manifest.csv"
    RemoteConfigUrl                   = $null
    EnableLogging                     = $false
    LogLevel                          = "INFO"
    AutoCleanupLogs                   = $true
    LogRetentionDays                  = 10
    MaxLogFiles                       = 15
    DownloadAllFiles                  = $false
    CucoDownloadUrl                   = 'https://cuco.inforlandia.pt/uagent/CtoolGui.exe'
    CucoBinaryPath                    = "cuco/CtoolGui.exe"
    DownloadCuco                      = $true
    CucoTargetDir                     = "Desktop"
    AskBeforeDownloadCuco             = $false
    MaxRetries                        = 5
    MaxBackoffSeconds                 = 60
    MinDiskSpaceMB                    = 3072
    CheckDiskSpace                    = $true
    MaxConcurrentDownloads            = 6
    SingleDownloadMode                = $false
    VerifyFileHashes                  = $false
    DeleteFilesOnHashMismatch         = $false
    HashMismatchPolicy                = 'Continue'
    HashVerifyMode                    = 'Parallel'
    HashVerifyMaxConcurrency          = 5
    # New defaults
    ScanOnlyMissingDrivers            = $true
    DeviceScanMode                    = 'Parallel'
    DeviceScanMaxConcurrency          = 8
    ClearWifiProfiles                 = $true
    AskBeforeClearingWifiProfiles     = $false
    WifiCleanupMode                   = 'SingleOnly'
    WifiProfileNameToDelete           = 'Null'
    AutoExitWithoutConfirmation       = $false
    ShowOnlyNonZeroStats              = $true
    ShowBanner                        = $true

    # Preflight checks
    PreflightEnabled                  = $true
    PreflightCheckAdmin               = $true
    PreflightCheckLogWritable         = $true
    PreflightCheckNetwork             = $true
    PreflightHttpTimeoutMs            = 4000
    PreflightCheckGitHub              = $true
    PreflightCheckBaseUrl             = $true
    PreflightCheckGoogle              = $true
    PreflightCheckCucoSite            = $true
    PreflightCucoUrl                  = 'https://cuco.inforlandia.pt/'
    PreflightPingEnabled              = $true
    PreflightPingTarget               = '1.1.1.1'
    PreflightPingTimeoutMs            = 2000
    PreflightPingLatencyWarnMs        = 150

    # Performance tweaks (Windows 10/11)
    DisableOneDriveStartup            = $true
    HideTaskViewButton                = $true
    DisableNewsAndInterestsAndWidgets = $true
    HideTaskbarSearch                 = $true
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
    }
    catch {
        Write-Warning "Failed to parse local defaults. Using internal defaults."
    }
}
else {
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
    }
    catch {
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
    }
    catch {
        Write-Warning "Failed to parse local overrides."
    }
}

function Import-AutoDerivaRemoteConfig {
    # .SYNOPSIS
    #     Downloads and parses a JSON configuration document from a URL.
    #
    # .DESCRIPTION
    #     Uses Invoke-WebRequest to fetch a JSON document and converts it to a PowerShell
    #     object via ConvertFrom-Json. Intended for centrally managed configuration
    #     overrides.
    #
    #     This function returns $null on failure and emits a warning instead of throwing,
    #     so the installer can continue using local configuration.
    #
    # .PARAMETER Url
    #     The URL to a JSON document containing configuration overrides.
    #
    # .OUTPUTS
    #     PSCustomObject or $null.
    #
    # .EXAMPLE
    #     $remote = Import-AutoDerivaRemoteConfig -Url 'https://example.com/autoderiva/config.json'
    param(
        [Parameter(Mandatory = $true)][string]$Url
    )

    try {
        Write-Host "Loading remote configuration overrides from: $Url" -ForegroundColor Cyan
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $remote = $resp.Content | ConvertFrom-Json
        if (-not $remote) { return $null }
        return $remote
    }
    catch {
        Write-Warning "Failed to load remote config overrides from '$Url': $_"
        return $null
    }
}

# 3. Optional: load remote config overrides (from config.json or CLI)
$remoteOverrideUrl = $null
try {
    if ($Config.RemoteConfigUrl) { $remoteOverrideUrl = [string]$Config.RemoteConfigUrl }
}
catch { $remoteOverrideUrl = $null }

if ($PSBoundParameters.ContainsKey('ConfigUrl') -and $ConfigUrl) {
    $remoteOverrideUrl = $ConfigUrl
}

if ($remoteOverrideUrl) {
    # In test mode, skip remote config fetch unless explicitly requested via -ConfigUrl
    if ($env:AUTODERIVA_TEST -eq '1' -and -not $PSBoundParameters.ContainsKey('ConfigUrl')) {
        Write-Verbose "AUTODERIVA_TEST set - skipping remote config override fetch (RemoteConfigUrl)."
    }
    else {
        $RemoteOverrides = Import-AutoDerivaRemoteConfig -Url $remoteOverrideUrl
        if ($RemoteOverrides) {
            foreach ($prop in $RemoteOverrides.PSObject.Properties) {
                $Config[$prop.Name] = $prop.Value
            }
        }
    }
}

# Apply SingleDownloadMode override
if ($Config.SingleDownloadMode) {
    Write-Host "Single Download Mode enabled. Forcing MaxConcurrentDownloads to 1." -ForegroundColor Yellow
    $Config.MaxConcurrentDownloads = 1
    # Single download mode forces a single concurrent worker; do not exit here
}

# Script flow flags (default)
$Script:ExitAfterDownloadAll = $false
$Script:ExitAfterDownloadCuco = $false
$Script:ExitAfterWifiCleanup = $false

# Apply CLI parameter overrides (if any)
if ($PSBoundParameters.Count -gt 0) {
    Write-Host "Applying CLI overrides..." -ForegroundColor Cyan

    if ($PSBoundParameters.ContainsKey('ConfigPath')) {
        if (Test-Path $ConfigPath) {
            try {
                $UserConfig = Get-Content $ConfigPath | ConvertFrom-Json
                foreach ($prop in $UserConfig.PSObject.Properties) { $Config[$prop.Name] = $prop.Value }
                Write-Host "Loaded configuration overrides from: $ConfigPath" -ForegroundColor Cyan
            }
            catch {
                Write-Warning "Failed to parse config at $ConfigPath. Ignoring."
            }
        }
        else {
            Write-Warning "Config file not found at: $ConfigPath"
        }
    }

    if ($PSBoundParameters.ContainsKey('EnableLogging')) { $Config.EnableLogging = $true }
    if ($PSBoundParameters.ContainsKey('NoLogCleanup')) { $Config.AutoCleanupLogs = $false }
    if ($PSBoundParameters.ContainsKey('LogRetentionDays') -and $LogRetentionDays -ge 0) { $Config.LogRetentionDays = $LogRetentionDays }
    if ($PSBoundParameters.ContainsKey('MaxLogFiles') -and $MaxLogFiles -ge 0) { $Config.MaxLogFiles = $MaxLogFiles }
    if ($PSBoundParameters.ContainsKey('DownloadAllFiles')) { $Config.DownloadAllFiles = $true }
    if ($PSBoundParameters.ContainsKey('DownloadAllAndExit')) { $Config.DownloadAllFiles = $true; $Script:ExitAfterDownloadAll = $true }
    if ($PSBoundParameters.ContainsKey('DownloadCuco')) { $Config.DownloadCuco = $true }
    if ($PSBoundParameters.ContainsKey('DownloadCucoAndExit')) { $Config.DownloadCuco = $true; $Script:ExitAfterDownloadCuco = $true }
    if ($PSBoundParameters.ContainsKey('CucoTargetDir') -and $CucoTargetDir) { $Config.CucoTargetDir = $CucoTargetDir }
    if ($PSBoundParameters.ContainsKey('AskBeforeDownloadCuco')) { $Config.AskBeforeDownloadCuco = $true }
    if ($PSBoundParameters.ContainsKey('NoAskBeforeDownloadCuco')) { $Config.AskBeforeDownloadCuco = $false }
    if ($PSBoundParameters.ContainsKey('SingleDownloadMode')) { $Config.MaxConcurrentDownloads = 1 }
    if ($PSBoundParameters.ContainsKey('MaxConcurrentDownloads') -and $MaxConcurrentDownloads -gt 0) { $Config.MaxConcurrentDownloads = $MaxConcurrentDownloads }
    if ($PSBoundParameters.ContainsKey('NoDiskSpaceCheck')) { $Config.CheckDiskSpace = $false }

    # File integrity verification
    if ($PSBoundParameters.ContainsKey('VerifyFileHashes')) { $Config.VerifyFileHashes = [bool]$VerifyFileHashes }
    if ($PSBoundParameters.ContainsKey('DeleteFilesOnHashMismatch')) { $Config.DeleteFilesOnHashMismatch = [bool]$DeleteFilesOnHashMismatch }
    if ($PSBoundParameters.ContainsKey('HashMismatchPolicy') -and $HashMismatchPolicy) { $Config.HashMismatchPolicy = $HashMismatchPolicy }
    if ($PSBoundParameters.ContainsKey('HashVerifyMode') -and $HashVerifyMode) { $Config.HashVerifyMode = $HashVerifyMode }
    if ($PSBoundParameters.ContainsKey('HashVerifyMaxConcurrency') -and $HashVerifyMaxConcurrency -gt 0) { $Config.HashVerifyMaxConcurrency = $HashVerifyMaxConcurrency }

    # Driver scan toggles
    if ($PSBoundParameters.ContainsKey('ScanOnlyMissingDrivers')) { $Config.ScanOnlyMissingDrivers = $true }
    if ($PSBoundParameters.ContainsKey('ScanAllDevices')) { $Config.ScanOnlyMissingDrivers = $false }

    # Wi-Fi cleanup toggles
    if ($PSBoundParameters.ContainsKey('ClearWifiAndExit')) { $Script:ExitAfterWifiCleanup = $true; $Config.ClearWifiProfiles = $true }
    if ($PSBoundParameters.ContainsKey('ClearWifiProfiles')) { $Config.ClearWifiProfiles = $true }
    if ($PSBoundParameters.ContainsKey('NoWifiCleanup')) { $Config.ClearWifiProfiles = $false; $Config.WifiCleanupMode = 'None' }
    if ($PSBoundParameters.ContainsKey('WifiCleanupMode') -and $WifiCleanupMode) { $Config.WifiCleanupMode = $WifiCleanupMode }
    if ($PSBoundParameters.ContainsKey('WifiProfileNameToDelete') -and $WifiProfileNameToDelete) { $Config.WifiProfileNameToDelete = $WifiProfileNameToDelete }
    if ($PSBoundParameters.ContainsKey('AskBeforeClearingWifiProfiles')) { $Config.AskBeforeClearingWifiProfiles = $true }
    if ($PSBoundParameters.ContainsKey('NoAskBeforeClearingWifiProfiles')) { $Config.AskBeforeClearingWifiProfiles = $false }

    # End-of-run toggles
    if ($PSBoundParameters.ContainsKey('AutoExitWithoutConfirmation')) { $Config.AutoExitWithoutConfirmation = $true }
    if ($PSBoundParameters.ContainsKey('RequireExitConfirmation')) { $Config.AutoExitWithoutConfirmation = $false }

    # Banner / UI toggles
    if ($PSBoundParameters.ContainsKey('ShowBanner')) { $Config.ShowBanner = [bool]$ShowBanner }

    # Performance tweaks (No* switches disable the tweak)
    if ($PSBoundParameters.ContainsKey('NoDisableOneDriveStartup')) { $Config.DisableOneDriveStartup = $false }
    if ($PSBoundParameters.ContainsKey('NoHideTaskViewButton')) { $Config.HideTaskViewButton = $false }
    if ($PSBoundParameters.ContainsKey('NoDisableNewsAndInterestsAndWidgets')) { $Config.DisableNewsAndInterestsAndWidgets = $false }
    if ($PSBoundParameters.ContainsKey('NoHideTaskbarSearch')) { $Config.HideTaskbarSearch = $false }

    # Performance tuning
    if ($PSBoundParameters.ContainsKey('DeviceScanMode') -and $DeviceScanMode) { $Config.DeviceScanMode = $DeviceScanMode }
    if ($PSBoundParameters.ContainsKey('DeviceScanMaxConcurrency') -and $DeviceScanMaxConcurrency -gt 0) { $Config.DeviceScanMaxConcurrency = $DeviceScanMaxConcurrency }

    # Stats display toggles
    if ($PSBoundParameters.ContainsKey('ShowOnlyNonZeroStats')) { $Config.ShowOnlyNonZeroStats = $true }
    if ($PSBoundParameters.ContainsKey('ShowAllStats')) { $Config.ShowOnlyNonZeroStats = $false }

    # Dry run flag - affects installation and downloads
    $Script:DryRun = $false
    if ($PSBoundParameters.ContainsKey('DryRun')) {
        $Script:DryRun = $true
        Write-Host "Dry run enabled - no changes will be applied." -ForegroundColor Yellow
    }

    if ($PSBoundParameters.ContainsKey('ShowConfig')) {
        Write-Host "Effective configuration:" -ForegroundColor Cyan
        # Write JSON to stdout with a stable prefix so it can be captured reliably by tools/tests
        $json = $Config | ConvertTo-Json -Depth 5
        Write-Output "AUTODERIVA::CONFIG::$json"
        return
    }
    
    # Print help and exit if requested
    if ($PSBoundParameters.ContainsKey('Help')) {
        $helpText = @"
Usage: Install-AutoDeriva.ps1 [options]

Options:
    -ConfigPath <path>           Use a custom config file as overrides (default: repo config.json if present).
    -ConfigUrl <url>             Load JSON config overrides from a URL (overrides config RemoteConfigUrl when provided).
    -EnableLogging              Enable logging (default from config: $($Config.EnableLogging)).
    -CleanLogs                  Delete ALL autoderiva-*.log files in the logs folder (default: disabled).
    -LogRetentionDays <n>       Auto-delete logs older than <n> days (default from config: $($Config.LogRetentionDays)).
    -MaxLogFiles <n>            Keep only the newest <n> logs (default from config: $($Config.MaxLogFiles)).
    -NoLogCleanup               Disable automatic log cleanup (default from config: $(-not $Config.AutoCleanupLogs)).
    -DownloadAllFiles           Download all files from manifest (default from config: $($Config.DownloadAllFiles)).
    -DownloadAllAndExit         Download all files then exit (alias: -DownloadOnly; default: disabled).
    -DownloadCuco               Download the Cuco utility (default from config: $($Config.DownloadCuco)).
    -DownloadCucoAndExit         Download Cuco then exit (alias: -CucoOnly; default: disabled).
    -CucoTargetDir <path>       Target dir for Cuco (default from config: $($Config.CucoTargetDir)).
    -AskBeforeDownloadCuco       Ask before downloading Cuco (default from config: $($Config.AskBeforeDownloadCuco)).
    -NoAskBeforeDownloadCuco     Disable the Cuco download prompt (default: disabled).
    -SingleDownloadMode         Force single-threaded downloads (default from config: $($Config.SingleDownloadMode)).
    -MaxConcurrentDownloads <n> Set max parallel downloads (default from config: $($Config.MaxConcurrentDownloads)).
    -NoDiskSpaceCheck           Skip pre-flight disk space check (default: disabled; config default: $(-not $Config.CheckDiskSpace)).

    -VerifyFileHashes <bool>     Enable/disable SHA256 verification using the manifest's Sha256 column (default from config: $($Config.VerifyFileHashes)).
    -DeleteFilesOnHashMismatch <bool> Delete a downloaded file when its SHA256 mismatches (default from config: $($Config.DeleteFilesOnHashMismatch)).
    -HashMismatchPolicy <mode>   On SHA256 mismatch: Continue|SkipDriver|Abort (default from config: $($Config.HashMismatchPolicy)).
    -HashVerifyMode <mode>       Hash verification mode: Parallel|Single (default from config: $($Config.HashVerifyMode)).
    -HashVerifyMaxConcurrency <n>Max parallel hash workers when HashVerifyMode=Parallel (default from config: $($Config.HashVerifyMaxConcurrency)).

    -ScanOnlyMissingDrivers      Only scan devices missing drivers (default from config: $($Config.ScanOnlyMissingDrivers)).
    -ScanAllDevices              Scan all present devices (overrides ScanOnlyMissingDrivers; default: disabled).

    -ExportUnknownDevicesCsv <path> Export devices missing drivers (ProblemCode 28) to a CSV file and exit.

    -ClearWifiAndExit            Only run Wi-Fi cleanup and exit (aliases: -WifiCleanupAndExit, -WifiOnly).
    -ClearWifiProfiles           Enable Wi-Fi cleanup at end (default from config: $($Config.ClearWifiProfiles)).
    -NoWifiCleanup               Disable Wi-Fi cleanup at end (default: disabled).
    -WifiCleanupMode <mode>      Wi-Fi cleanup mode: SingleOnly|All|None (default from config: $($Config.WifiCleanupMode)).
    -WifiProfileNameToDelete <n> Profile name used by SingleOnly mode (default from config: $($Config.WifiProfileNameToDelete)).
                                Aliases: -WifiName, -WifiProfileName
    -AskBeforeClearingWifiProfiles   Ask before deleting Wi-Fi profiles (default from config: $($Config.AskBeforeClearingWifiProfiles)).
    -NoAskBeforeClearingWifiProfiles Disable Wi-Fi deletion prompt (default: disabled).

    -AutoExitWithoutConfirmation Exit without waiting at end (default from config: $($Config.AutoExitWithoutConfirmation)).
    -RequireExitConfirmation     Force waiting at end (default: disabled).

    -ShowBanner <bool>          Enable/disable printing the startup banner (default from config: $($Config.ShowBanner)).

    -NoDisableOneDriveStartup    Do NOT disable OneDrive auto-start for this run (tweak enabled by default).
    -NoHideTaskViewButton        Do NOT hide the Task View button for this run.
    -NoDisableNewsAndInterestsAndWidgets Do NOT disable News/Interests (Win10) and Widgets (Win11) for this run.
    -NoHideTaskbarSearch         Do NOT hide the Search icon/box on the taskbar for this run.

    -DeviceScanMode <mode>       Device scan mode: Parallel|Single (default from config: $($Config.DeviceScanMode)).
    -DeviceScanMaxConcurrency <n> Max parallel workers for device scan (ProblemCode queries) when DeviceScanMode=Parallel (default from config: $($Config.DeviceScanMaxConcurrency)).

    -ShowOnlyNonZeroStats        Only show counters above 0 in Statistics (default from config: $($Config.ShowOnlyNonZeroStats)).
    -ShowAllStats                Show all counters including zeros (default: disabled).

    -ShowConfig                 Print the effective configuration and exit (default: disabled).
    -DryRun                     Dry run (no downloads or installs; default: disabled).
    -Help, -?                   Show this help message and exit.
"@
        Write-Host $helpText
        return
    }
}

# Initialize Stats
$Script:Stats = @{
    StartTime                  = Get-Date
    EndTime                    = $null
    DriversScanned             = 0
    DriversMatched             = 0
    FilesDownloaded            = 0
    FilesDownloadFailed        = 0
    DriversSkipped             = 0
    DriversAlreadyPresent      = 0
    DriversInstalled           = 0
    DriversFailed              = 0
    RebootsRequired            = 0
    CucoDownloaded             = 0
    CucoDownloadFailed         = 0
    CucoSkipped                = 0
    UnknownDriversAfterInstall = 0
}

# Section timing tracking (elapsed time per section between Write-Section calls)
$Script:SectionTimings = New-Object System.Collections.Generic.List[object]
$Script:CurrentSectionTitle = $null
$Script:CurrentSectionStart = $null

function Format-AutoDerivaDuration {
    param(
        [Parameter(Mandatory = $true)][TimeSpan]$Duration
    )

    $totalSeconds = 0
    try { $totalSeconds = [int][Math]::Floor($Duration.TotalSeconds) } catch { $totalSeconds = 0 }
    if ($totalSeconds -lt 0) { $totalSeconds = 0 }

    $hours = [int]($totalSeconds / 3600)
    $minutes = [int](($totalSeconds % 3600) / 60)
    $seconds = [int]($totalSeconds % 60)
    return ('{0:D2}:{1:D2}:{2:D2}' -f $hours, $minutes, $seconds)
}

function Complete-AutoDerivaSectionTiming {
    param(
        [Parameter(Mandatory = $true)][DateTime]$Now
    )

    if (-not $Script:CurrentSectionTitle) { return }
    if (-not $Script:CurrentSectionStart) { return }

    $elapsed = $Now - $Script:CurrentSectionStart
    $Script:SectionTimings.Add([PSCustomObject]@{
            Title   = [string]$Script:CurrentSectionTitle
            Elapsed = $elapsed
        })
}

function Write-AutoDerivaStatText {
    # .SYNOPSIS
    #     Writes a stat line with a non-numeric value.
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Value,
        [string]$Color = 'Cyan'
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { $Value = '' }

    try {
        Write-Host "   [" -NoNewline -ForegroundColor $Script:ColorDim
        Write-Host "STAT" -NoNewline -ForegroundColor $Color
        Write-Host ("] {0} : {1}" -f $Label, $Value) -ForegroundColor $Script:ColorText
    }
    catch {
        Write-Output ("STAT {0} : {1}" -f $Label, $Value)
    }

    if ($LogFilePath) {
        try {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -Path $LogFilePath -Value ("[$timestamp] [INFO] {0} : {1}" -f $Label, $Value) -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Failed to write stat text to log file: $_"
        }
    }
}

function Write-AutoDerivaStat {
    # .SYNOPSIS
    #     Writes a single statistic counter line.
    #
    # .DESCRIPTION
    #     Prints one stat line directly to the console (so it is visible regardless of
    #     configured LogLevel). When `ShowOnlyNonZeroStats` is enabled in the effective
    #     config, counters with value 0 (or less) are suppressed.
    #
    # .PARAMETER Label
    #     The label to display (left side).
    #
    # .PARAMETER Value
    #     The numeric value to display.
    #
    # .PARAMETER Color
    #     The console color used for the value line.
    #
    # .OUTPUTS
    #     None.
    #
    # .EXAMPLE
    #     Write-AutoDerivaStat -Label 'Drivers Installed' -Value 12 -Color Green
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int]$Value,
        [string]$Color = 'Cyan'
    )

    $onlyNonZero = $true
    try { $onlyNonZero = [bool]$Config.ShowOnlyNonZeroStats } catch { $onlyNonZero = $true }
    if ($onlyNonZero -and $Value -le 0) { return }

    # Stats should be visible regardless of configured LogLevel.
    try {
        Write-Host "   [" -NoNewline -ForegroundColor $Script:ColorDim
        Write-Host "STAT" -NoNewline -ForegroundColor $Color
        Write-Host ("] {0} : {1}" -f $Label, $Value) -ForegroundColor $Script:ColorText
    }
    catch {
        # Fallback for constrained hosts
        Write-Output ("STAT {0} : {1}" -f $Label, $Value)
    }

    if ($LogFilePath) {
        try {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -Path $LogFilePath -Value ("[$timestamp] [INFO] {0} : {1}" -f $Label, $Value) -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Failed to write stat to log file: $_"
        }
    }
}

function Test-AutoDerivaPromptAvailable {
    # .SYNOPSIS
    #     Determines whether it is safe to prompt the user for input.
    #
    # .DESCRIPTION
    #     Returns $true only when:
    #     - The script is not running under AUTODERIVA_TEST=1
    #     - The host is interactive
    #     - Console input is not redirected
    #
    #     This prevents hangs in CI/scheduled tasks and in VS Code integrated terminals
    #     where interactive reads can be unreliable.
    #
    # .OUTPUTS
    #     Boolean.
    #
    # .EXAMPLE
    #     if (Test-AutoDerivaPromptAvailable) { Read-Host 'Continue?' }
    # Avoid hanging in non-interactive contexts (scheduled tasks/CI) and during tests
    if ($env:AUTODERIVA_TEST -eq '1') { return $false }
    if ($env:CI -eq '1' -or $env:GITHUB_ACTIONS -eq 'true') { return $false }

    # VS Code integrated terminals can be interactive but Read-Host/Console APIs are
    # flaky (and can hang). Be conservative there.
    if ($env:TERM_PROGRAM -eq 'vscode' -or $env:VSCODE_PID) { return $false }
    try {
        if (-not [Environment]::UserInteractive) { return $false }
    }
    catch { return $false }

    try {
        if ([Console]::IsInputRedirected) { return $false }
    }
    catch {
        # If Console APIs aren't available, still try prompting on ConsoleHost.
        try {
            if ($Host -and $Host.Name -eq 'ConsoleHost') { return $true }
        }
        catch { Write-Verbose "Prompt availability check failed: $_" }
        return $true
    }

    return $true
}

function Wait-AutoDerivaExit {
    # .SYNOPSIS
    #     Waits for the user to exit the script (Enter or Ctrl+C).
    #
    # .DESCRIPTION
    #     Displays a "Press Enter" prompt and polls Console key input. Also registers a
    #     Ctrl+C (CancelKeyPress) handler so the user can exit without entering input.
    #
    #     The wait is skipped when AutoExit is provided or when prompts are not safe
    #     (see Test-AutoDerivaPromptAvailable).
    #
    # .PARAMETER AutoExit
    #     When set, the function returns immediately without waiting.
    #
    # .OUTPUTS
    #     None.
    #
    # .EXAMPLE
    #     Wait-AutoDerivaExit -AutoExit:$false
    param(
        [switch]$AutoExit,
        [switch]$Force
    )

    if ($AutoExit) { return }
    $promptOk = $false
    try { $promptOk = (Test-AutoDerivaPromptAvailable) } catch { $promptOk = $false }
    if (-not $promptOk -and -not $Force) {
        # Best-effort: in classic console hosts, still pause to prevent the window
        # from closing immediately when launched via cmd.exe /c or file association.
        $safeToPrompt = $false
        try {
            $safeToPrompt = ([Environment]::UserInteractive -and ($Host.Name -eq 'ConsoleHost'))
            if ($env:TERM_PROGRAM -eq 'vscode' -or $env:VSCODE_PID) { $safeToPrompt = $false }
            if ($env:CI -eq '1' -or $env:GITHUB_ACTIONS -eq 'true') { $safeToPrompt = $false }
            if ($env:AUTODERIVA_TEST -eq '1') { $safeToPrompt = $false }
        }
        catch { $safeToPrompt = $false }

        if ($safeToPrompt) {
            try { $null = Read-Host 'Press Enter to close this window...' }
            catch { Write-Verbose "Read-Host failed in best-effort pause: $_" }
        }
        return
    }
    if (-not $promptOk -and $Force) {
        try { $null = Read-Host 'Press Enter to close this window...' }
        catch { Write-Verbose "Read-Host failed in forced wait: $_" }
        return
    }

    $message = 'Press Enter to close this window (or Ctrl+C)...'
    try { Write-Host $message -ForegroundColor Gray } catch { Write-Verbose "Write-Host failed: $_" }

    $script:__AutoDerivaCtrlC = $false
    $handler = $null

    try {
        $handler = [ConsoleCancelEventHandler] {
            param($ctrlCSource, $cancelEvent)
            [void]$ctrlCSource
            $script:__AutoDerivaCtrlC = $true
            $cancelEvent.Cancel = $true
        }
        try { [Console]::add_CancelKeyPress($handler) } catch { Write-Verbose "Failed to register Ctrl+C handler: $_" }

        while ($true) {
            if ($script:__AutoDerivaCtrlC) { break }

            try {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -eq [ConsoleKey]::Enter) { break }
                }
                else {
                    Start-Sleep -Milliseconds 100
                }
            }
            catch {
                # Fallback: if key polling isn't supported, try Read-Host once.
                try { $null = Read-Host $message } catch { Write-Verbose "Read-Host failed: $_" }
                break
            }
        }
    }
    finally {
        if ($handler) {
            try { [Console]::remove_CancelKeyPress($handler) } catch { Write-Verbose "Failed to remove Ctrl+C handler: $_" }
        }
        Remove-Variable -Name __AutoDerivaCtrlC -Scope Script -ErrorAction SilentlyContinue
    }
}

function Invoke-AutoDerivaLogCleanup {
    # .SYNOPSIS
    #     Deletes old AutoDeriva log files based on retention rules.
    #
    # .DESCRIPTION
    #     Removes log files matching `autoderiva-*.log` under the specified directory.
    #     Supports either:
    #     - Force deletion of all matching logs, or
    #     - Age-based deletion (`RetentionDays`) and count-based deletion (`MaxFiles`).
    #
    # .PARAMETER RootPath
    #     Directory containing AutoDeriva log files.
    #
    # .PARAMETER RetentionDays
    #     Delete logs older than this many days. Use 0 to disable age-based cleanup.
    #
    # .PARAMETER MaxFiles
    #     Keep at most this many newest logs. Use 0 to disable count-based cleanup.
    #
    # .PARAMETER ForceAll
    #     When set, deletes all `autoderiva-*.log` files in RootPath.
    #
    # .OUTPUTS
    #     None.
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [int]$RetentionDays,
        [int]$MaxFiles,
        [switch]$ForceAll
    )

    $pattern = 'autoderiva-*.log'
    $logs = @(Get-ChildItem -Path $RootPath -Filter $pattern -File -ErrorAction SilentlyContinue)
    if ($logs.Count -eq 0) { return }

    if ($ForceAll) {
        $logs | Remove-Item -Force -ErrorAction SilentlyContinue
        return
    }

    # Age-based cleanup (0 or negative disables)
    if ($RetentionDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        $old = $logs | Where-Object { $_.LastWriteTime -lt $cutoff }
        if ($old.Count -gt 0) {
            $old | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    # Count-based cleanup (0 or negative disables)
    if ($MaxFiles -gt 0) {
        $remaining = @(Get-ChildItem -Path $RootPath -Filter $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending)

        if ($remaining.Count -gt $MaxFiles) {
            $toDelete = $remaining | Select-Object -Skip $MaxFiles
            $toDelete | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-AutoDerivaLogDirectory {
    # .SYNOPSIS
    #     Returns the log directory for this repository.
    #
    # .DESCRIPTION
    #     Computes the `logs/` folder path under the repository root.
    #
    # .PARAMETER RepoRoot
    #     Repository root directory.
    #
    # .OUTPUTS
    #     String.
    param([string]$RepoRoot)
    return (Join-Path $RepoRoot 'logs')
}

# In test mode, default to no file logging (and avoid cleanup) unless explicitly forced.
if ($env:AUTODERIVA_TEST -eq '1' -and -not $PSBoundParameters.ContainsKey('EnableLogging')) {
    $Config.EnableLogging = $false
}

# Log cleanup/retention (before creating a new log file)
if ($PSBoundParameters.ContainsKey('CleanLogs')) {
    try {
        $logDir = Get-AutoDerivaLogDirectory -RepoRoot $Script:RepoRoot
        Invoke-AutoDerivaLogCleanup -RootPath $logDir -ForceAll
        Write-Host "Cleaned existing AutoDeriva logs in: $logDir" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to clean existing logs: $_"
    }
}
elseif ($Config.EnableLogging -and $Config.AutoCleanupLogs -and $env:AUTODERIVA_TEST -ne '1') {
    try {
        $logDir = Get-AutoDerivaLogDirectory -RepoRoot $Script:RepoRoot
        Invoke-AutoDerivaLogCleanup -RootPath $logDir -RetentionDays $Config.LogRetentionDays -MaxFiles $Config.MaxLogFiles
    }
    catch {
        Write-Warning "Log cleanup failed: $_"
    }
}

# Initialize Log
if ($Config.EnableLogging) {
    $LogFileName = "autoderiva-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $LogDir = Get-AutoDerivaLogDirectory -RepoRoot $Script:RepoRoot
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
    }
    catch {
        Write-Warning "Could not create log directory at $LogDir. Logging to console only."
        $LogDir = $null
    }

    $LogFilePath = if ($LogDir) { Join-Path $LogDir $LogFileName } else { $null }
    try {
        if ($LogFilePath) {
            "AutoDeriva Log Started: $(Get-Date)" | Out-File -FilePath $LogFilePath -Encoding utf8 -Force
            Write-Host "Logging enabled. Log file: $LogFilePath" -ForegroundColor Gray
        }
        else {
            Write-Host "Logging enabled. (console-only)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "Could not write to log file at $LogFilePath. Logging to console only."
        $LogFilePath = $null
    }
}
else {
    $LogFilePath = $null
}

# TUI Colors
$Script:ColorHeader = "Cyan"
$Script:ColorText = "White"
$Script:ColorAccent = "Blue"
$Script:ColorDim = "Gray"

# Provide minimal stubs for key commands so test frameworks (Pester v5+) can Mock them
# without failing when the real implementations are not yet loaded (or an early exit
# prevented full dot-sourcing). These stubs are no-ops and will not override real
# implementations if they are defined later in the file.
if (-not (Get-Command Invoke-DownloadFile -ErrorAction SilentlyContinue)) {
    function Invoke-DownloadFile {
        param($Url, $OutputPath, $MaxRetries = $Config.MaxRetries)
        $null = $Url
        $null = $OutputPath
        $null = $MaxRetries
        return $false
    }
}
if (-not (Get-Command Get-RemoteCsv -ErrorAction SilentlyContinue)) {
    function Get-RemoteCsv {
        param($Url)
        $null = $Url
        return @()
    }
}

# .SYNOPSIS
#     Displays the AutoDeriva brand header.
# .DESCRIPTION
#     Clears the host and prints the ASCII art logo and title.
function Write-BrandHeader {
    # Set Background Color
    try {
        $Host.UI.RawUI.BackgroundColor = "Black"
    }
    catch {
        Write-Verbose "Could not set background color."
    }
    Clear-Host
    
    $Art = @(
        ' *        .        *        .        *        .',
        '   .        *          .        *        .        *',
        '        *        .        *        .        *        .',
        '   .        *        .        *        .        *        .',
        '',
        "             ' | ` ",
        '      ________ |________',
        '     \__________________/',
        '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
        '   ~~~~~~\____/~~~~\____/~~~~\____/~~~~\____/~~~~~~',
        ' ~~~~~\____/~~~~\____/~~~~\____/~~~~\____/~~~~\____/~~~~'
    )
    
    $Rainbow = @('Red', 'DarkYellow', 'Yellow', 'Green', 'Magenta', 'DarkMagenta')
    $SeaColors = @('Cyan', 'DarkCyan', 'Blue', 'DarkBlue')
    
    for ($i = 0; $i -lt $Art.Count; $i++) {
        if ($i -ge 9) {
            $Color = $SeaColors[$i % $SeaColors.Count]
        }
        else {
            $Color = $Rainbow[$i % $Rainbow.Count]
        }
        Write-Host $Art[$i] -ForegroundColor $Color
    }
    
    Write-Host "`n"
    Write-Host "   " ("=" * 60) -ForegroundColor $Script:ColorAccent
    Write-Host "   System Setup & Driver Installer" -ForegroundColor $Script:ColorDim
    Write-Host "   " ("=" * 60) -ForegroundColor $Script:ColorAccent
    Write-Host "`n"
}

# .SYNOPSIS
#     Writes a section header to the console and log file.
# .PARAMETER Title
#     The title of the section.
function Write-Section {
    param(
        [string]$Title,
        [switch]$NoTiming
    )

    if (-not $NoTiming) {
        try {
            $now = Get-Date
            Complete-AutoDerivaSectionTiming -Now $now
            $Script:CurrentSectionTitle = $Title
            $Script:CurrentSectionStart = $now
        }
        catch {
            Write-Verbose "Section timing update failed: $_"
        }
    }

    Write-Host "`n   [$Title]" -ForegroundColor $Script:ColorHeader
    Write-Host "   " ("-" * ($Title.Length + 2)) -ForegroundColor $Script:ColorAccent
    if ($LogFilePath) {
        Add-Content -Path $LogFilePath -Value "`n[$Title]" -ErrorAction SilentlyContinue
    }
}

# .SYNOPSIS
#     Writes a log message to the console and log file.
# .PARAMETER Status
#     The status tag (e.g., INFO, ERROR, SUCCESS).
# .PARAMETER Message
#     The message to log.
# .PARAMETER Color
#     The color of the status tag in the console.
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
        "DEBUG" { $CurrentLevel = "DEBUG" }
        "WARN" { $CurrentLevel = "WARN" }
        "ERROR" { $CurrentLevel = "ERROR" }
        "FATAL" { $CurrentLevel = "FATAL" }
        "SUCCESS" { $CurrentLevel = "INFO" }
        "PROCESS" { $CurrentLevel = "INFO" }
        "INSTALL" { $CurrentLevel = "INFO" }
        "START" { $CurrentLevel = "INFO" }
        "DONE" { $CurrentLevel = "INFO" }
        default { $CurrentLevel = "INFO" }
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

# .SYNOPSIS
#     Formats a byte count into a human-readable string.
# .PARAMETER Bytes
#     The number of bytes.
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

function Get-AutoDerivaSha256Hex {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $stream = $null
    $sha = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    }
    catch {
        Write-Verbose "Failed to compute SHA256 for file: $Path. Error: $_"
        return $null
    }
    finally {
        if ($sha) {
            try { $sha.Dispose() }
            catch { Write-Verbose "Failed to dispose SHA256 object: $_" }
        }
        if ($stream) {
            try { $stream.Dispose() }
            catch { Write-Verbose "Failed to dispose file stream for SHA256: $_" }
        }
    }
}

function Test-AutoDerivaFileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) { return $true }

    $expected = $ExpectedSha256.Trim()
    if ($expected -notmatch '^[0-9a-fA-F]{64}$') {
        Write-Verbose "Expected SHA256 is not a 64-hex string for file: $Path. Expected: $expected"
        return $false
    }

    $actual = Get-AutoDerivaSha256Hex -Path $Path
    if ([string]::IsNullOrWhiteSpace($actual)) { return $false }
    return ($actual -eq $expected.ToLowerInvariant())
}

function Invoke-DownloadedFileHashVerification {
    param(
        [Parameter(Mandatory = $true)]$FileList
    )

    $verify = $false
    try { $verify = [bool]$Config.VerifyFileHashes } catch { $verify = $false }
    if (-not $verify) { return }

    $deleteOnMismatch = $false
    try { $deleteOnMismatch = [bool]$Config.DeleteFilesOnHashMismatch } catch { $deleteOnMismatch = $false }

    $mismatchedDriverInfs = @()

    $mode = 'Parallel'
    try {
        if ($Config.HashVerifyMode) { $mode = [string]$Config.HashVerifyMode }
    }
    catch { $mode = 'Parallel' }
    if ($mode -notin @('Parallel', 'Single')) { $mode = 'Parallel' }

    $maxConcurrency = 5
    try {
        if ($Config.HashVerifyMaxConcurrency -and [int]$Config.HashVerifyMaxConcurrency -gt 0) {
            $maxConcurrency = [int]$Config.HashVerifyMaxConcurrency
        }
    }
    catch { $maxConcurrency = 5 }
    if ($maxConcurrency -le 0) { $maxConcurrency = 5 }
    if ($mode -eq 'Single') { $maxConcurrency = 1 }

    $toCheck = @()
    $sawAnyHashField = $false
    foreach ($f in $FileList) {
        if (-not $f) { continue }
        if (-not ($f.ContainsKey('ExpectedSha256'))) { continue }
        $sawAnyHashField = $true
        $expected = [string]$f.ExpectedSha256
        if ([string]::IsNullOrWhiteSpace($expected)) { continue }
        if (-not (Test-Path -LiteralPath $f.OutputPath)) { continue }
        $toCheck += $f
    }
    if ($toCheck.Count -eq 0) {
        if (-not $sawAnyHashField) {
            Write-AutoDerivaLog 'WARN' 'VerifyFileHashes is enabled but no SHA256 values were provided (manifest missing hashes). Skipping hash verification.' 'Yellow'
        }
        return @{ CheckedCount = 0; MismatchCount = 0; MismatchedDriverInfs = @() }
    }

    $mismatch = 0
    $checked = 0

    if ($mode -eq 'Single') {
        foreach ($f in $toCheck) {
            $checked++
            $ok = $false
            try {
                $ok = Test-AutoDerivaFileHash -Path $f.OutputPath -ExpectedSha256 ([string]$f.ExpectedSha256)
            }
            catch { $ok = $false }

            if (-not $ok) {
                $mismatch++
                if ($f.ContainsKey('DriverInf') -and $f.DriverInf) { $mismatchedDriverInfs += [string]$f.DriverInf }
                $rp = if ($f.ContainsKey('RelativePath')) { [string]$f.RelativePath } else { $null }
                $label = if ($rp) { $rp } else { [string]$f.OutputPath }
                if ($deleteOnMismatch) {
                    Write-AutoDerivaLog 'ERROR' "SHA256 mismatch (deleted): $label" 'Red'
                    try { Remove-Item -LiteralPath $f.OutputPath -Force -ErrorAction SilentlyContinue }
                    catch { Write-Verbose "Failed to remove file after SHA mismatch: $($f.OutputPath): $_" }
                }
                else {
                    Write-AutoDerivaLog 'WARN' "SHA256 mismatch (kept): $label" 'Yellow'
                }

                $Script:Stats.FilesDownloadFailed++
                if ($Script:Stats.FilesDownloaded -gt 0) { $Script:Stats.FilesDownloaded-- }
            }
        }
    }
    else {
        $runspacePool = $null
        $jobs = @()
        $scriptBlock = {
            param($Path, $Expected)
            $ErrorActionPreference = 'Stop'
            $stream = $null
            $sha = $null
            try {
                $stream = [System.IO.File]::OpenRead($Path)
                $sha = [System.Security.Cryptography.SHA256]::Create()
                $hashBytes = $sha.ComputeHash($stream)
                $actual = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
                $exp = ([string]$Expected).Trim().ToLowerInvariant()
                return @{ Ok = ($actual -eq $exp); Actual = $actual }
            }
            finally {
                if ($sha) {
                    try { $sha.Dispose() }
                    catch { Write-Verbose "Failed to dispose SHA256 object in runspace: $_" }
                }
                if ($stream) {
                    try { $stream.Dispose() }
                    catch { Write-Verbose "Failed to dispose SHA256 stream in runspace: $_" }
                }
            }
        }

        $parallelOk = $false
        try {
            # Test hook: force runspace pooling to fail
            if ($Script:Test_FailHashRunspacePool) { throw 'Test forced hash runspace pool failure' }

            $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxConcurrency)
            $runspacePool.Open()

            foreach ($f in $toCheck) {
                $ps = [powershell]::Create().AddScript($scriptBlock).AddArgument([string]$f.OutputPath).AddArgument([string]$f.ExpectedSha256)
                $ps.RunspacePool = $runspacePool
                $jobs += @{ PS = $ps; Handle = $ps.BeginInvoke(); File = $f }
            }

            foreach ($job in $jobs) {
                $result = $null
                try {
                    $result = $job.PS.EndInvoke($job.Handle)
                }
                catch {
                    $result = @{ Ok = $false; Actual = $null }
                }
                finally {
                    $checked++
                    try { $job.PS.Dispose() }
                    catch { Write-Verbose "Failed to dispose hash runspace PowerShell instance: $_" }
                }

                if (-not ($result -and $result.Ok)) {
                    $mismatch++
                    $f = $job.File
                    if ($f.ContainsKey('DriverInf') -and $f.DriverInf) { $mismatchedDriverInfs += [string]$f.DriverInf }
                    $rp = if ($f.ContainsKey('RelativePath')) { [string]$f.RelativePath } else { $null }
                    $label = if ($rp) { $rp } else { [string]$f.OutputPath }
                    if ($deleteOnMismatch) {
                        Write-AutoDerivaLog 'ERROR' "SHA256 mismatch (deleted): $label" 'Red'
                        try { Remove-Item -LiteralPath $f.OutputPath -Force -ErrorAction SilentlyContinue }
                        catch { Write-Verbose "Failed to remove file after SHA mismatch: $($f.OutputPath): $_" }
                    }
                    else {
                        Write-AutoDerivaLog 'WARN' "SHA256 mismatch (kept): $label" 'Yellow'
                    }

                    $Script:Stats.FilesDownloadFailed++
                    if ($Script:Stats.FilesDownloaded -gt 0) { $Script:Stats.FilesDownloaded-- }
                }
            }

            $parallelOk = $true
        }
        catch {
            Write-AutoDerivaLog 'WARN' "Parallel SHA256 verification unavailable; falling back to Single. Error: $_" 'Yellow'
        }
        finally {
            foreach ($job in $jobs) {
                if (-not $job) { continue }
                try { $job.PS.Dispose() } catch { Write-Verbose "Failed to dispose hash runspace PowerShell instance during cleanup: $_" }
            }

            if ($runspacePool) {
                try { $runspacePool.Close() }
                catch { Write-Verbose "Failed to close hash runspace pool: $_" }
                try { $runspacePool.Dispose() }
                catch { Write-Verbose "Failed to dispose hash runspace pool: $_" }
            }
        }

        if (-not $parallelOk) {
            foreach ($f in $toCheck) {
                $ok = $false
                try {
                    $ok = Test-AutoDerivaFileHash -Path $f.OutputPath -ExpectedSha256 ([string]$f.ExpectedSha256)
                }
                catch { $ok = $false }

                if (-not $ok) {
                    $mismatch++
                    if ($f.ContainsKey('DriverInf') -and $f.DriverInf) { $mismatchedDriverInfs += [string]$f.DriverInf }
                    $rp = if ($f.ContainsKey('RelativePath')) { [string]$f.RelativePath } else { $null }
                    $label = if ($rp) { $rp } else { [string]$f.OutputPath }
                    if ($deleteOnMismatch) {
                        Write-AutoDerivaLog 'ERROR' "SHA256 mismatch (deleted): $label" 'Red'
                        try { Remove-Item -LiteralPath $f.OutputPath -Force -ErrorAction SilentlyContinue }
                        catch { Write-Verbose "Failed to remove file after SHA mismatch: $($f.OutputPath): $_" }
                    }
                    else {
                        Write-AutoDerivaLog 'WARN' "SHA256 mismatch (kept): $label" 'Yellow'
                    }

                    $Script:Stats.FilesDownloadFailed++
                    if ($Script:Stats.FilesDownloaded -gt 0) { $Script:Stats.FilesDownloaded-- }
                }
            }
        }
    }

    if ($mismatch -gt 0) {
        Write-AutoDerivaLog 'WARN' "SHA256 verification failed for $mismatch file(s)." 'Yellow'
    }

    return @{
        CheckedCount         = $checked
        MismatchCount        = $mismatch
        MismatchedDriverInfs = ($mismatchedDriverInfs | Where-Object { $_ } | Select-Object -Unique)
    }
}

# .SYNOPSIS
#     Downloads a file from a URL to a local path with retry logic and exponential backoff.
# .PARAMETER Url
#     The URL of the file to download.
# .PARAMETER OutputPath
#     The local path where the file should be saved.
# .PARAMETER MaxRetries
#     Number of times to retry the download.
# .OUTPUTS
#     Boolean. True if successful, False otherwise.
function Invoke-DownloadFile {
    param($Url, $OutputPath, $MaxRetries = $Config.MaxRetries)
    if ($Script:DryRun) {
        Write-AutoDerivaLog "INFO" "DryRun: Skipping download of $Url to $OutputPath" "Gray"
        # Ensure directory exists for downstream checks
        $dir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        return $true
    }

    # Test hook: allow tests to inject a custom download behavior without using Pester's Mock
    if ($Script:Test_InvokeDownloadFile) {
        return & $Script:Test_InvokeDownloadFile -Url $Url -OutputPath $OutputPath -MaxRetries $MaxRetries
    }
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
            }
            catch {
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

# .SYNOPSIS
#     Checks if there is enough free disk space on the drive.
# .PARAMETER Path
#     The path to check.
# .PARAMETER MinMB
#     Minimum required space in Megabytes.
# .OUTPUTS
#     Boolean.
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
    }
    catch {
        Write-AutoDerivaLog "WARN" "Could not verify disk space: $_" "Yellow"
        return $true # Assume true on error to avoid blocking
    }
}

# .SYNOPSIS
#     Fetches a CSV file from a remote URL and parses it.
# .PARAMETER Url
#     The URL of the CSV file.
# .OUTPUTS
#     PSCustomObject[]. The parsed CSV data.
function Get-RemoteCsv {
    param($Url)
    if ($Script:CsvCache.ContainsKey($Url)) {
        Write-AutoDerivaLog "INFO" "Using cached data for: $Url" "Cyan"
        return $Script:CsvCache[$Url]
    }

    # Test hook: allow tests to inject CSV data without performing network requests
    if ($Script:Test_GetRemoteCsv) {
        return & $Script:Test_GetRemoteCsv -Url $Url
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

# .SYNOPSIS
#     Performs pre-flight checks before starting the installation.
# .DESCRIPTION
#     Checks for internet connectivity.
function Test-PreFlight {
    $preflightEnabled = $true
    try { $preflightEnabled = [bool]$Config.PreflightEnabled } catch { $preflightEnabled = $true }
    if (-not $preflightEnabled) { return }

    Write-Section 'Preflight Checks'

    $httpTimeoutMs = 4000
    try {
        if ($Config.PreflightHttpTimeoutMs -and [int]$Config.PreflightHttpTimeoutMs -gt 0) {
            $httpTimeoutMs = [int]$Config.PreflightHttpTimeoutMs
        }
    }
    catch { $httpTimeoutMs = 4000 }

    $writeOk = {
        param([string]$Name, [string]$Detail)
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'OK' }
        Write-AutoDerivaLog 'SUCCESS' ("{0}: {1}" -f $Name, $Detail) 'Green'
    }
    $writeWarn = {
        param([string]$Name, [string]$Detail)
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'Warning' }
        Write-AutoDerivaLog 'WARN' ("{0}: {1}" -f $Name, $Detail) 'Yellow'
    }
    # Admin check
    $isAdmin = $false
    $checkAdmin = $true
    try { $checkAdmin = [bool]$Config.PreflightCheckAdmin } catch { $checkAdmin = $true }
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
    }
    catch {
        $isAdmin = $false
    }
    if ($checkAdmin) {
        if ($isAdmin) { & $writeOk 'Admin' 'Running elevated' } else { & $writeWarn 'Admin' 'Not elevated (some operations may be skipped/fail)' }
    }

    # Log writable check (best-effort)
    $checkLogWritable = $true
    try { $checkLogWritable = [bool]$Config.PreflightCheckLogWritable } catch { $checkLogWritable = $true }
    try {
        if (-not $checkLogWritable) {
            Write-AutoDerivaLog 'INFO' 'Logging: Skipped (disabled by config)' 'Gray'
        }
        elseif (-not $Config.EnableLogging) {
            Write-AutoDerivaLog 'INFO' 'Logging: Disabled (skipping log writable check)' 'Gray'
        }
        elseif (-not $LogFilePath) {
            & $writeWarn 'Logging' 'Log file path not set (console-only logging)' 
        }
        else {
            try {
                Add-Content -Path $LogFilePath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Preflight: log writable check" -ErrorAction Stop
                & $writeOk 'Logging' ("Writable ({0})" -f $LogFilePath)
            }
            catch {
                & $writeWarn 'Logging' ("Not writable ({0})" -f $LogFilePath)
            }
        }
    }
    catch {
        & $writeWarn 'Logging' 'Could not verify log writability'
    }

    # Disk space check (uses existing logic; non-fatal here)
    try {
        if ($Config.CheckDiskSpace) {
            $pathToCheck = $env:TEMP
            if (-not $pathToCheck) { $pathToCheck = '.' }
            [void](Test-DiskSpace -Path $pathToCheck)
        }
        else {
            Write-AutoDerivaLog 'INFO' 'Disk Space: Skipped (disabled by config)' 'Gray'
        }
    }
    catch {
        & $writeWarn 'Disk Space' 'Could not verify'
    }

    # Network checks: keep fast; never fatal. Skipped in AUTODERIVA_TEST to avoid noisy/flaky CI.
    $checkNetwork = $true
    try { $checkNetwork = [bool]$Config.PreflightCheckNetwork } catch { $checkNetwork = $true }
    if (-not $checkNetwork) {
        Write-AutoDerivaLog 'INFO' 'Network: Skipped (disabled by config)' 'Gray'
        return
    }

    $allowNetworkInTest = $false
    try { $allowNetworkInTest = [bool]$Script:Test_PreflightAllowInTest } catch { $allowNetworkInTest = $false }
    if ($env:AUTODERIVA_TEST -eq '1' -and -not $allowNetworkInTest -and -not $Script:Test_InvokePreflightHttpCheck -and -not $Script:Test_InvokePreflightPing) {
        Write-AutoDerivaLog 'INFO' 'Network: Skipped (AUTODERIVA_TEST=1)' 'Gray'
        return
    }

    $invokeHttpCheck = {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$Url,
            [ValidateSet('GET', 'HEAD')][string]$Method = 'HEAD',
            [int]$TimeoutMs = 4000,
            [switch]$AllowGetFallback
        )

        if ($Script:Test_InvokePreflightHttpCheck) {
            return & $Script:Test_InvokePreflightHttpCheck -Name $Name -Url $Url -Method $Method -TimeoutMs $TimeoutMs -AllowGetFallback:$AllowGetFallback
        }

        $doRequest = {
            param([string]$ReqMethod)
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = $ReqMethod
            $req.Timeout = $TimeoutMs
            $req.ReadWriteTimeout = $TimeoutMs
            $req.AllowAutoRedirect = $true
            $req.UserAgent = 'AutoDeriva-Preflight'
            return $req.GetResponse()
        }

        try {
            $resp = & $doRequest -ReqMethod $Method
            try {
                $code = 0
                try { $code = [int]$resp.StatusCode } catch { $code = 0 }
                if ($code -ge 200 -and $code -lt 400) {
                    & $writeOk $Name ("HTTP {0}" -f $code)
                }
                else {
                    & $writeWarn $Name ("HTTP {0}" -f $code)
                }
            }
            finally {
                try { $resp.Close() } catch { Write-Verbose "Failed to close HTTP response for ${Name}: $_" }
            }
        }
        catch {
            $statusMsg = $null
            try {
                if ($_.Exception -is [System.Net.WebException]) {
                    $webResp = $_.Exception.Response
                    if ($webResp -and ($webResp -is [System.Net.HttpWebResponse])) {
                        $code = [int]$webResp.StatusCode
                        $desc = [string]$webResp.StatusDescription
                        $statusMsg = "HTTP $code $desc"
                    }
                }
            }
            catch {
                $statusMsg = $null
            }

            if ($AllowGetFallback -and $Method -eq 'HEAD' -and ($statusMsg -match '^HTTP\s+(400|403|405)\b')) {
                try {
                    $resp2 = & $doRequest -ReqMethod 'GET'
                    try {
                        $code2 = 0
                        try { $code2 = [int]$resp2.StatusCode } catch { $code2 = 0 }
                        if ($code2 -ge 200 -and $code2 -lt 400) {
                            & $writeOk $Name ("HTTP {0} (GET fallback)" -f $code2)
                            return
                        }
                        & $writeWarn $Name ("HTTP {0} (GET fallback)" -f $code2)
                        return
                    }
                    finally {
                        try { $resp2.Close() } catch { Write-Verbose "Failed to close HTTP response for ${Name} (fallback): $_" }
                    }
                }
                catch {
                    Write-Verbose "Preflight HTTP GET fallback failed for ${Name}: $_"
                }
            }

            $msg = $statusMsg
            if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $_.Exception.Message }
            & $writeWarn $Name $msg
        }
    }

    # Internet (DNS)
    try {
        [void][System.Net.Dns]::GetHostEntry('github.com')
        & $writeOk 'Internet (DNS)' 'Resolved github.com'
    }
    catch {
        & $writeWarn 'Internet (DNS)' 'DNS resolution failed'
    }

    # GitHub (web) + GitHub content base (raw)
    $checkGitHub = $true
    try { $checkGitHub = [bool]$Config.PreflightCheckGitHub } catch { $checkGitHub = $true }
    if ($checkGitHub) {
        & $invokeHttpCheck -Name 'GitHub' -Url 'https://github.com/' -Method 'GET' -TimeoutMs $httpTimeoutMs
    }
    try {
        $baseUrl = $null
        try { $baseUrl = [string]$Config.BaseUrl } catch { $baseUrl = $null }
        $checkBaseUrl = $true
        try { $checkBaseUrl = [bool]$Config.PreflightCheckBaseUrl } catch { $checkBaseUrl = $true }
        if ($checkBaseUrl -and -not [string]::IsNullOrWhiteSpace($baseUrl) -and ($baseUrl -match '^https?://')) {
            & $invokeHttpCheck -Name 'GitHub (BaseUrl)' -Url $baseUrl -Method 'HEAD' -TimeoutMs $httpTimeoutMs -AllowGetFallback
        }
    }
    catch {
        Write-Verbose "Failed to check BaseUrl connectivity: $_"
    }

    # Google (generate_204 is a lightweight connectivity endpoint)
    $checkGoogle = $true
    try { $checkGoogle = [bool]$Config.PreflightCheckGoogle } catch { $checkGoogle = $true }
    if ($checkGoogle) {
        & $invokeHttpCheck -Name 'Google' -Url 'https://www.google.com/generate_204' -Method 'GET' -TimeoutMs $httpTimeoutMs
    }

    # Cuco reachability check
    $checkCuco = $false
    try { $checkCuco = [bool]$Config.PreflightCheckCucoSite } catch { $checkCuco = $false }
    if ($checkCuco) {
        $cucoUrl = 'https://cuco.inforlandia.pt/'
        try { if ($Config.PreflightCucoUrl) { $cucoUrl = [string]$Config.PreflightCucoUrl } } catch { $cucoUrl = 'https://cuco.inforlandia.pt/' }
        if (-not [string]::IsNullOrWhiteSpace($cucoUrl)) {
            & $invokeHttpCheck -Name 'Cuco' -Url $cucoUrl -Method 'GET' -TimeoutMs $httpTimeoutMs
        }
    }

    # Ping check (ICMP may be blocked; warn-only)
    $checkPing = $true
    try { $checkPing = [bool]$Config.PreflightPingEnabled } catch { $checkPing = $true }
    if ($checkPing) {
        $pingTarget = '1.1.1.1'
        $pingTimeoutMs = 2000
        $warnLatencyMs = 150
        try { if ($Config.PreflightPingTarget) { $pingTarget = [string]$Config.PreflightPingTarget } } catch { $pingTarget = '1.1.1.1' }
        try { if ($Config.PreflightPingTimeoutMs -and [int]$Config.PreflightPingTimeoutMs -gt 0) { $pingTimeoutMs = [int]$Config.PreflightPingTimeoutMs } } catch { $pingTimeoutMs = 2000 }
        try { if ($Config.PreflightPingLatencyWarnMs -and [int]$Config.PreflightPingLatencyWarnMs -gt 0) { $warnLatencyMs = [int]$Config.PreflightPingLatencyWarnMs } } catch { $warnLatencyMs = 150 }

        try {
            $reply = $null
            if ($Script:Test_InvokePreflightPing) {
                $reply = & $Script:Test_InvokePreflightPing -Target $pingTarget -TimeoutMs $pingTimeoutMs
            }
            else {
                $ping = New-Object System.Net.NetworkInformation.Ping
                $reply = $ping.Send($pingTarget, $pingTimeoutMs)
            }

            if ($reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $rt = 0
                try { $rt = [int]$reply.RoundtripTime } catch { $rt = 0 }
                if ($rt -ge $warnLatencyMs) {
                    & $writeWarn 'Ping' ("{0} in {1}ms (>= {2}ms: potential slow connection)" -f $pingTarget, $rt, $warnLatencyMs)
                }
                else {
                    & $writeOk 'Ping' ("{0} in {1}ms" -f $pingTarget, $rt)
                }
            }
            else {
                $status = if ($reply) { [string]$reply.Status } else { 'No reply' }
                & $writeWarn 'Ping' $status
            }
        }
        catch {
            & $writeWarn 'Ping' ($_.Exception.Message)
        }
    }
}

function Get-DeviceProblemCode {
    # .SYNOPSIS
    #     Reads the PnP ProblemCode for a device instance.
    #
    # .DESCRIPTION
    #     Uses Get-PnpDeviceProperty with DEVPKEY_Device_ProblemCode. Returns $null if
    #     the property cannot be retrieved (e.g., missing permissions or not supported).
    #
    # .PARAMETER InstanceId
    #     The device InstanceId from Get-PnpDevice.
    #
    # .OUTPUTS
    #     Int32 or $null.
    #
    # .EXAMPLE
    #     $code = Get-DeviceProblemCode -InstanceId $dev.InstanceId
    param(
        [Parameter(Mandatory = $true)][string]$InstanceId
    )

    try {
        $prop = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop
        if ($null -ne $prop -and $null -ne $prop.Data) {
            return [int]$prop.Data
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-MissingDriverDevice {
    # .SYNOPSIS
    #     Filters devices to those missing drivers.
    #
    # .DESCRIPTION
    #     Given a list of PnP devices (from Get-PnpDevice), returns only those whose
    #     ProblemCode equals 28 ("drivers not installed").
    #
    # .PARAMETER SystemDevices
    #     Collection of devices returned by Get-PnpDevice.
    #
    # .OUTPUTS
    #     Object[]. Subset of the input device objects.
    param(
        [Parameter(Mandatory = $true)]$SystemDevices
    )

    $devices = @($SystemDevices | Where-Object { $_ -and ($_.PSObject.Properties.Name -contains 'InstanceId') -and $_.InstanceId })
    if ($devices.Count -eq 0) { return @() }

    $showScanProgress = $true
    if ($env:AUTODERIVA_TEST -eq '1') { $showScanProgress = $false }
    if ($env:CI -eq '1' -or $env:GITHUB_ACTIONS -eq 'true') { $showScanProgress = $false }

    # Parallelize the per-device ProblemCode query (Get-PnpDeviceProperty) via runspaces.
    # This can be a noticeable speedup on systems with lots of devices.
    $mode = 'Parallel'
    try {
        if ($Config.DeviceScanMode) { $mode = [string]$Config.DeviceScanMode }
    }
    catch { $mode = 'Parallel' }

    $maxConcurrency = 8
    try {
        if ($Config.DeviceScanMaxConcurrency -and [int]$Config.DeviceScanMaxConcurrency -gt 0) {
            $maxConcurrency = [int]$Config.DeviceScanMaxConcurrency
        }
    }
    catch { $maxConcurrency = 8 }

    if ($mode -eq 'Single') { $maxConcurrency = 1 }

    $totalDevices = [int]$devices.Count
    $progressStep = 0
    if ($totalDevices -ge 20) {
        try { $progressStep = [Math]::Max([int][Math]::Floor($totalDevices / 10), 1) } catch { $progressStep = 0 }
    }

    if ($showScanProgress) {
        $modeText = if ($maxConcurrency -le 1) { 'Single' } else { "Parallel ($maxConcurrency)" }
        Write-AutoDerivaLog 'INFO' "Checking driver status (ProblemCode) for $totalDevices device(s) [$modeText]..." 'Gray'
    }

    if ($maxConcurrency -le 1) {
        $results = @()
        $done = 0
        foreach ($dev in $devices) {
            $code = Get-DeviceProblemCode -InstanceId $dev.InstanceId
            $results += [PSCustomObject]@{ InstanceId = $dev.InstanceId; ProblemCode = $code }

            if ($showScanProgress) {
                $done++
                if (($progressStep -gt 0 -and ($done % $progressStep) -eq 0) -or $done -eq $totalDevices) {
                    Write-AutoDerivaLog 'INFO' "Scanning devices: $done/$totalDevices" 'Gray'
                }
            }
        }

        $missingInstanceIds = @($results | Where-Object { $_ -and $_.ProblemCode -eq 28 } | ForEach-Object { $_.InstanceId })
        if ($missingInstanceIds.Count -eq 0) { return @() }

        $missing = @()
        foreach ($dev in $devices) {
            if ($missingInstanceIds -contains $dev.InstanceId) { $missing += $dev }
        }
        return $missing
    }
    $results = @()

    try {
        $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, $maxConcurrency)
        $runspacePool.Open()

        $jobs = New-Object System.Collections.Generic.List[object]
        foreach ($dev in $devices) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $runspacePool
            $null = $ps.AddScript({
                    param($instanceId)
                    try {
                        Import-Module PnpDevice -ErrorAction SilentlyContinue | Out-Null
                        $prop = Get-PnpDeviceProperty -InstanceId $instanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop
                        $val = $null
                        try { $val = [int]$prop.Data } catch { $val = $null }
                        return [PSCustomObject]@{ InstanceId = $instanceId; ProblemCode = $val }
                    }
                    catch {
                        return [PSCustomObject]@{ InstanceId = $instanceId; ProblemCode = $null }
                    }
                }).AddArgument($dev.InstanceId)

            $handle = $ps.BeginInvoke()
            $jobs.Add([PSCustomObject]@{ PowerShell = $ps; Handle = $handle })
        }

        $done = 0
        foreach ($job in $jobs) {
            try {
                $out = $job.PowerShell.EndInvoke($job.Handle)
                if ($out) { $results += $out }

                if ($showScanProgress) {
                    $done++
                    if (($progressStep -gt 0 -and ($done % $progressStep) -eq 0) -or $done -eq $totalDevices) {
                        Write-AutoDerivaLog 'INFO' "Scanning devices: $done/$totalDevices" 'Gray'
                    }
                }
            }
            finally {
                try { $job.PowerShell.Dispose() } catch { Write-Verbose "Failed to dispose PowerShell job: $_" }
            }
        }
    }
    catch {
        Write-Verbose "Parallel missing-driver scan unavailable; falling back to single. Error: $_"
        $results = @()
        foreach ($dev in $devices) {
            $code = Get-DeviceProblemCode -InstanceId $dev.InstanceId
            $results += [PSCustomObject]@{ InstanceId = $dev.InstanceId; ProblemCode = $code }
        }
    }
    finally {
        if ($runspacePool) {
            try { $runspacePool.Close() } catch { Write-Verbose "Failed to close RunspacePool: $_" }
            try { $runspacePool.Dispose() } catch { Write-Verbose "Failed to dispose RunspacePool: $_" }
        }
    }

    $missingInstanceIds = @($results | Where-Object { $_ -and $_.ProblemCode -eq 28 } | ForEach-Object { $_.InstanceId })
    if ($missingInstanceIds.Count -eq 0) { return @() }

    $missing = @()
    foreach ($dev in $devices) {
        if ($missingInstanceIds -contains $dev.InstanceId) { $missing += $dev }
    }
    return $missing
}

function Get-SystemHardware {
    # .SYNOPSIS
    #     Retrieves the Hardware IDs of the current system.
    # .OUTPUTS
    #     String[]. A list of Hardware IDs.
    [CmdletBinding()]
    param(
        [switch]$AllDevices
    )

    Write-Section "Hardware Detection"
    Write-AutoDerivaLog "INFO" "Scanning system devices..." "Cyan"

    # Test hook: allow tests or tooling to inject hardware IDs without querying PnP
    if ($Script:Test_GetSystemHardware) {
        $ids = @(& $Script:Test_GetSystemHardware)
        $ids = $ids | Where-Object { $_ } | ForEach-Object { $_.ToUpper() }
        $Script:Stats.DriversScanned = $ids.Count
        Write-AutoDerivaLog "INFO" "Found $( $ids.Count ) active hardware IDs (test hook)." "Green"
        return $ids
    }

    try {
        $SystemDevices = Get-PnpDevice -PresentOnly -ErrorAction Stop
        if (-not $SystemDevices) { throw "Get-PnpDevice returned no results." }
    }
    catch {
        throw "Failed to query system devices: $_"
    }

    $effectiveOnlyMissing = $false
    if (-not $AllDevices) {
        try { $effectiveOnlyMissing = [bool]$Config.ScanOnlyMissingDrivers } catch { $effectiveOnlyMissing = $false }
    }

    if ($effectiveOnlyMissing) {
        $missingDevices = Get-MissingDriverDevice -SystemDevices $SystemDevices
        Write-AutoDerivaLog "INFO" "Filtering to devices missing drivers (ProblemCode 28)." "Gray"
        $SystemDevices = $missingDevices
    }

    $SystemHardwareIds = $SystemDevices.HardwareID | Where-Object { $_ } | ForEach-Object { $_.ToUpper() }
    $Script:Stats.DriversScanned = $SystemHardwareIds.Count
    Write-AutoDerivaLog "INFO" "Found $( $SystemHardwareIds.Count ) active hardware IDs." "Green"
    return $SystemHardwareIds
}

function Get-UnknownDriverDeviceCount {
    # .SYNOPSIS
    #     Counts how many present devices are missing drivers.
    #
    # .DESCRIPTION
    #     Computes the number of present devices with ProblemCode 28. A test hook
    #     (`$Script:Test_GetUnknownDriverCount`) can override the computation.
    #
    # .OUTPUTS
    #     Int32.
    # "Unknown" here means devices still missing drivers (ProblemCode 28)
    try {
        if ($Script:Test_GetUnknownDriverCount) {
            return [int](& $Script:Test_GetUnknownDriverCount)
        }

        $SystemDevices = Get-PnpDevice -PresentOnly -ErrorAction Stop
        if (-not $SystemDevices) { return 0 }
        $missing = Get-MissingDriverDevice -SystemDevices $SystemDevices
        return [int]$missing.Count
    }
    catch {
        Write-Verbose "Failed to compute unknown driver count: $_"
        return 0
    }
}

function Export-AutoDerivaUnknownDevicesCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    Write-Section 'Unknown Devices Export'

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'ExportUnknownDevicesCsv path is empty.'
    }

    $outDir = $null
    try { $outDir = Split-Path -Path $Path -Parent } catch { $outDir = $null }
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    # Test hook: allow deterministic export content without querying PnP.
    if ($Script:Test_GetUnknownDevicesForExport) {
        $rows = @(& $Script:Test_GetUnknownDevicesForExport)
        $rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        Write-AutoDerivaLog 'SUCCESS' "Exported $(($rows | Measure-Object).Count) unknown device(s) to: $Path" 'Green'
        return
    }

    try { Import-Module PnpDevice -ErrorAction SilentlyContinue | Out-Null }
    catch { Write-Verbose "Failed to import PnpDevice module: $_" }

    $systemDevices = $null
    try {
        $systemDevices = Get-PnpDevice -PresentOnly -ErrorAction Stop
    }
    catch {
        throw "Failed to query PnP devices for export: $_"
    }

    $missing = Get-MissingDriverDevice -SystemDevices $systemDevices
    $rows = @()
    foreach ($dev in @($missing)) {
        if (-not $dev) { continue }
        $instanceId = $null
        try { $instanceId = [string]$dev.InstanceId } catch { $instanceId = $null }
        if (-not $instanceId) { continue }

        $hwids = @()
        try {
            $prop = Get-PnpDeviceProperty -InstanceId $instanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop
            if ($prop -and $prop.Data) { $hwids = @($prop.Data) }
        }
        catch { $hwids = @() }

        $rows += [PSCustomObject]@{
            InstanceId   = $instanceId
            FriendlyName = (try { [string]$dev.FriendlyName } catch { '' })
            Name         = (try { [string]$dev.Name } catch { '' })
            Class        = (try { [string]$dev.Class } catch { '' })
            Manufacturer = (try { [string]$dev.Manufacturer } catch { '' })
            Status       = (try { [string]$dev.Status } catch { '' })
            ProblemCode  = 28
            HardwareIds  = (($hwids | Where-Object { $_ }) -join ';')
        }
    }

    $rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    Write-AutoDerivaLog 'SUCCESS' "Exported $($rows.Count) unknown device(s) to: $Path" 'Green'
}

function Clear-WifiProfile {
    # .SYNOPSIS
    #     Deletes saved Wi-Fi profiles according to configuration.
    #
    # .DESCRIPTION
    #     Enumerates Wi-Fi profiles using `netsh wlan show profiles` and deletes profiles
    #     using `netsh wlan delete profile`. Behavior is controlled by config:
    #     - ClearWifiProfiles (master enable)
    #     - WifiCleanupMode: SingleOnly|All|None
    #     - WifiProfileNameToDelete (used by SingleOnly)
    #     - AskBeforeClearingWifiProfiles (optional confirmation)
    #
    #     This operation is skipped when AUTODERIVA_TEST=1.
    #
    # .OUTPUTS
    #     None.
    # Deletes all saved Wi-Fi profiles when enabled via config.
    if ($env:AUTODERIVA_TEST -eq '1') {
        Write-Verbose 'AUTODERIVA_TEST set - skipping Wi-Fi profile deletion.'
        return
    }

    $enabled = $false
    $ask = $false
    $mode = 'SingleOnly'
    $targetName = 'Null'

    try { $enabled = [bool]$Config.ClearWifiProfiles } catch { $enabled = $false }
    try { $ask = [bool]$Config.AskBeforeClearingWifiProfiles } catch { $ask = $false }
    try { if ($Config.WifiCleanupMode) { $mode = [string]$Config.WifiCleanupMode } } catch { $mode = 'SingleOnly' }
    try { if ($Config.WifiProfileNameToDelete) { $targetName = [string]$Config.WifiProfileNameToDelete } } catch { $targetName = 'Null' }

    if (-not $enabled) { return }
    if ($mode -eq 'None') { return }

    $profiles = @()
    try {
        $output = & netsh.exe wlan show profiles 2>$null
        foreach ($line in $output) {
            $m = [regex]::Match($line, 'All\s+User\s+Profile\s*:\s*(.+)$')
            if ($m.Success) {
                $name = $m.Groups[1].Value.Trim()
                if ($name) { $profiles += $name }
            }
        }
        $profiles = $profiles | Select-Object -Unique
    }
    catch {
        Write-AutoDerivaLog 'WARN' "Failed to enumerate Wi-Fi profiles: $_" 'Yellow'
        return
    }

    if ($profiles.Count -eq 0) {
        Write-AutoDerivaLog 'INFO' 'No saved Wi-Fi profiles found.' 'Gray'
        return
    }

    $profilesToDelete = @($profiles)
    if ($mode -eq 'SingleOnly') {
        $profilesToDelete = @($profiles | Where-Object { $_ -and $_.Trim() -ieq $targetName })
        if ($profilesToDelete.Count -eq 0) {
            Write-AutoDerivaLog 'INFO' "Wi-Fi profile '$targetName' not found; nothing to delete." 'Gray'
            return
        }
    }

    $doDelete = $true
    if ($ask) {
        if (-not (Test-AutoDerivaPromptAvailable)) {
            Write-AutoDerivaLog 'WARN' 'Wi-Fi deletion confirmation requested but no interactive input available. Skipping Wi-Fi profile deletion.' 'Yellow'
            return
        }
        $prompt = if ($mode -eq 'SingleOnly') { "Delete saved Wi-Fi profile '$targetName'? (y/N)" } else { 'Delete all saved Wi-Fi profiles? (y/N)' }
        $resp = $null
        try { $resp = Read-Host $prompt } catch { $resp = $null }
        $doDelete = ($resp -match '^(y|yes)$')
    }

    if (-not $doDelete) {
        Write-AutoDerivaLog 'INFO' 'Wi-Fi profile deletion skipped by user.' 'Gray'
        return
    }

    Write-Section 'Wi-Fi Cleanup'
    Write-AutoDerivaLog 'INFO' "Deleting $( $profilesToDelete.Count ) saved Wi-Fi profile(s) (mode: $mode)..." 'Cyan'
    foreach ($p in $profilesToDelete) {
        try {
            & netsh.exe wlan delete profile name="$p" | Out-Null
        }
        catch {
            Write-AutoDerivaLog 'WARN' "Failed to delete Wi-Fi profile '$p': $_" 'Yellow'
        }
    }
    Write-AutoDerivaLog 'SUCCESS' 'Wi-Fi profile deletion complete.' 'Green'
}

# .SYNOPSIS
#     Finds compatible drivers from the inventory based on system Hardware IDs.
# .PARAMETER DriverInventory
#     The driver inventory list.
# .PARAMETER SystemHardwareIds
#     The list of system Hardware IDs.
# .OUTPUTS
#     PSCustomObject[]. A list of compatible driver objects.
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

# .SYNOPSIS
#     Downloads and installs the matched drivers.
# .PARAMETER DriverMatches
#     The list of compatible drivers.
# .PARAMETER TempDir
#     The temporary directory to use for downloads.
# .OUTPUTS
#     PSCustomObject[]. List of installation results.
function Install-Driver {
    param($DriverMatches, $TempDir)
    
    $Results = @()

    $driverCount = 0
    if ($DriverMatches) { $driverCount = $DriverMatches.Count }
    if ($driverCount -eq 0) {
        Write-AutoDerivaLog "INFO" "No compatible drivers found in the inventory." "Yellow"
        return $Results
    }

    Write-AutoDerivaLog "SUCCESS" "Found $driverCount compatible drivers." "Green"
    
    # Fetch File Manifest
    Write-Section "File Manifest & Download"
    $ManifestUrl = $Config.BaseUrl + $Config.ManifestPath
    $FileManifest = Get-RemoteCsv -Url $ManifestUrl
    
    # Group matches by INF path to avoid duplicate downloads. Be defensive in case
    # the inventory CSV is missing the expected `InfPath` property on some rows.
    $UniqueInfs = @()
    foreach ($drv in $DriverMatches) {
        $infCandidate = $null
        if ($drv.PSObject.Properties.Name -contains 'InfPath' -and $drv.InfPath) {
            $infCandidate = $drv.InfPath
        }
        elseif ($drv.PSObject.Properties.Name -contains 'INFPath' -and $drv.INFPath) {
            $infCandidate = $drv.INFPath
        }
        elseif ($drv.PSObject.Properties.Name -contains 'FileName' -and $drv.FileName) {
            # Try to resolve the INF path using the file manifest (best-effort)
            $match = $FileManifest | Where-Object { $_.FileName -eq $drv.FileName } | Select-Object -First 1
            if ($match) {
                # Prefer an AssociatedInf mapping if available, otherwise use the relative path of the INF itself
                if ($match.AssociatedInf) { $infCandidate = $match.AssociatedInf } else { $infCandidate = $match.RelativePath }
            }
        }
        if ($infCandidate) { $UniqueInfs += $infCandidate } else {
            $name = if ($drv.PSObject.Properties.Name -contains 'FileName') { $drv.FileName } elseif ($drv.PSObject.Properties.Name -contains 'HardwareIDs') { $drv.HardwareIDs } else { $drv | Out-String }
            Write-AutoDerivaLog "WARN" "Driver record missing InfPath property (could not resolve): $name" "Yellow"
            # Record skipped driver due to missing INF path so callers/tests receive a result entry
            $Script:Stats.DriversSkipped++
            $Results += [PSCustomObject]@{ Driver = $name; Status = "Skipped (No Inf)"; Details = "Missing InfPath" }
        }
    }
    $UniqueInfs = $UniqueInfs | Where-Object { $_ } | Select-Object -Unique
    
    # 1. Collect all files to download
    $AllFilesToDownload = @()
    $DriversToInstall = @() # Keep track of valid drivers (those with files)

    foreach ($infPath in $UniqueInfs) {
        $TargetInf = $infPath.Replace('\', '/')
        $DriverFiles = $FileManifest | Where-Object { $_.AssociatedInf -eq $TargetInf }
        
        if (-not $DriverFiles) {
            Write-AutoDerivaLog "WARN" "No files found in manifest for $infPath" "Yellow"
            $Script:Stats.DriversSkipped++
            $Results += [PSCustomObject]@{ Driver = $infPath; Status = "Skipped (No Files)"; Details = "Manifest missing files" }
            continue
        }
        
        $DriversToInstall += $infPath
        
        foreach ($file in $DriverFiles) {
            $remoteUrl = $Config.BaseUrl + $file.RelativePath
            $localPath = Join-Path $TempDir $file.RelativePath.Replace('/', '\')
            $expected = $null
            if ($file.PSObject.Properties.Name -contains 'Sha256') { $expected = $file.Sha256 }
            $AllFilesToDownload += @{ Url = $remoteUrl; OutputPath = $localPath; RelativePath = $file.RelativePath; ExpectedSha256 = $expected; DriverInf = $TargetInf }
        }
    }
    
    # 2. Download concurrently
    $policy = 'Continue'
    $mismatchedInfSet = $null
    if ($AllFilesToDownload.Count -gt 0) {
        Invoke-ConcurrentDownload -FileList $AllFilesToDownload -MaxConcurrency $Config.MaxConcurrentDownloads

        $hashResult = Invoke-DownloadedFileHashVerification -FileList $AllFilesToDownload
        $mismatchedInfSet = $null
        $policy = 'Continue'
        try {
            if ($Config.HashMismatchPolicy) { $policy = [string]$Config.HashMismatchPolicy }
        }
        catch { $policy = 'Continue' }
        if ($policy -notin @('Continue', 'SkipDriver', 'Abort')) { $policy = 'Continue' }

        $mismatchedInfs = @()
        if ($hashResult -and $hashResult.MismatchedDriverInfs) { $mismatchedInfs = @($hashResult.MismatchedDriverInfs) }
        if ($mismatchedInfs.Count -gt 0) {
            $mismatchedInfSet = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($mi in $mismatchedInfs) { if ($mi) { [void]$mismatchedInfSet.Add(([string]$mi).ToLowerInvariant()) } }
        }

        if ($hashResult -and $hashResult.MismatchCount -gt 0 -and $policy -eq 'Abort') {
            Write-AutoDerivaLog 'ERROR' "SHA256 mismatch policy is Abort. Aborting driver installation." 'Red'

            foreach ($infPath in $DriversToInstall) {
                $ti = $infPath.Replace('\\', '/').ToLowerInvariant()
                if ($mismatchedInfSet -and $mismatchedInfSet.Contains($ti)) {
                    $Script:Stats.DriversFailed++
                    $Results += [PSCustomObject]@{ Driver = $infPath; Status = 'Failed (Hash Mismatch)'; Details = 'Hash mismatch policy: Abort' }
                }
                else {
                    $Script:Stats.DriversSkipped++
                    $Results += [PSCustomObject]@{ Driver = $infPath; Status = 'Skipped (Aborted)'; Details = 'Hash mismatch policy: Abort' }
                }
            }

            return $Results
        }
    }
    
    # 3. Install Drivers
    $totalDrivers = $DriversToInstall.Count
    $currentDriverIndex = 0
    
    foreach ($infPath in $DriversToInstall) {
        $currentDriverIndex++
        $driverPercent = [math]::Min(100, [int](($currentDriverIndex / $totalDrivers) * 100))
        Write-Progress -Id 1 -Activity "Installing Drivers" -Status "Processing $infPath ($currentDriverIndex/$totalDrivers)" -PercentComplete $driverPercent
        
        Write-AutoDerivaLog "PROCESS" "Processing driver: $infPath" "Cyan"

        # Apply hash mismatch policy per driver if requested
        if ($policy -eq 'SkipDriver' -and $mismatchedInfSet) {
            $ti = $infPath.Replace('\\', '/').ToLowerInvariant()
            if ($mismatchedInfSet.Contains($ti)) {
                Write-AutoDerivaLog 'WARN' "Skipping driver due to SHA256 mismatch (policy: SkipDriver): $infPath" 'Yellow'
                $Script:Stats.DriversSkipped++
                $Results += [PSCustomObject]@{ Driver = $infPath; Status = 'Skipped (Hash Mismatch)'; Details = 'Hash mismatch policy: SkipDriver' }
                continue
            }
        }
        
        $LocalInfPath = Join-Path $TempDir $infPath.Replace('/', '\')
        
        if (Test-Path $LocalInfPath) {
            Write-AutoDerivaLog "INSTALL" "Installing driver..." "Cyan"
            if ($Script:DryRun) {
                Write-AutoDerivaLog "INFO" "DryRun: Skipping installation of $LocalInfPath" "Gray"
                $proc = @{ ExitCode = 0 }
            }
            else {
                $proc = Start-Process -FilePath "pnputil.exe" -ArgumentList "/add-driver `"$LocalInfPath`" /install" -NoNewWindow -Wait -PassThru
            }
            
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010 -or $proc.ExitCode -eq 259) {
                # 3010 = Reboot required, 259 = Already present / no action
                if ($proc.ExitCode -eq 259) {
                    Write-AutoDerivaLog "INFO" "Driver already present or no action needed (Exit Code 259)." "Yellow"
                    $status = "Installed (Already Present)"
                    $Script:Stats.DriversAlreadyPresent++
                    $Script:Stats.DriversInstalled++
                }
                else {
                    Write-AutoDerivaLog "SUCCESS" "Driver installed successfully." "Green"
                    $Script:Stats.DriversInstalled++
                    $status = "Installed"
                }
                if ($proc.ExitCode -eq 3010) { 
                    $Script:Stats.RebootsRequired++ 
                    $status = "Installed (Reboot Req)"
                }
                $Results += [PSCustomObject]@{ Driver = $infPath; Status = $status; Details = "Success" }
            }
            else {
                Write-AutoDerivaLog "ERROR" "Driver installation failed. Exit Code: $($proc.ExitCode)" "Red"
                $Script:Stats.DriversFailed++
                $Results += [PSCustomObject]@{ Driver = $infPath; Status = "Failed"; Details = "PnPUtil Exit Code $($proc.ExitCode)" }
            }
        }
        else {
            Write-AutoDerivaLog "ERROR" "INF file not found after download: $LocalInfPath" "Red"
            $Results += [PSCustomObject]@{ Driver = $infPath; Status = "Failed"; Details = "INF Missing" }
        }
    }
    Write-Progress -Id 1 -Activity "Installing Drivers" -Status "Completed" -PercentComplete 100
    Write-Progress -Id 1 -Activity "Installing Drivers" -Completed
    return $Results
}

# .SYNOPSIS
#     Downloads the Cuco binary to the configured directory.
function Install-Cuco {
    if (-not $Config.DownloadCuco) {
        Write-AutoDerivaLog "INFO" "Cuco download is disabled in configuration." "Gray"
        $Script:Stats.CucoSkipped++
        return
    }

    $askCuco = $false
    try { $askCuco = [bool]$Config.AskBeforeDownloadCuco } catch { $askCuco = $false }
    if ($askCuco) {
        if (-not (Test-AutoDerivaPromptAvailable)) {
            Write-AutoDerivaLog 'WARN' 'Cuco download confirmation requested but no interactive input available. Skipping Cuco download.' 'Yellow'
            $Script:Stats.CucoSkipped++
            return
        }

        $resp = $null
        try { $resp = Read-Host 'Download Cuco utility? (y/N)' } catch { $resp = $null }
        $doDownload = ($resp -match '^(y|yes)$')
        if (-not $doDownload) {
            Write-AutoDerivaLog 'INFO' 'Cuco download skipped by user.' 'Gray'
            $Script:Stats.CucoSkipped++
            return
        }
    }

    Write-Section "Cuco Utility"
    
    $TargetDir = $Config.CucoTargetDir
    
    # Resolve "Desktop" to the actual user's desktop if possible
    if ($TargetDir -eq "Desktop") {
        # Default to current environment's desktop (Admin if elevated)
        $TargetDir = [Environment]::GetFolderPath("Desktop")
        
        # Try to find the original user's desktop if running as Admin
        # This is a best-effort attempt using the explorer.exe process owner
        try {
            $explorerProc = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($explorerProc -and $explorerProc.UserName) {
                $userName = $explorerProc.UserName.Split('\')[-1]
                # Construct path assuming standard profile location
                $userDesktop = Join-Path "C:\Users" $userName
                $userDesktop = Join-Path $userDesktop "Desktop"
                if (Test-Path $userDesktop) {
                    $TargetDir = $userDesktop
                    Write-AutoDerivaLog "INFO" "Detected user desktop: $TargetDir" "Gray"
                }
            }
        }
        catch {
            Write-Verbose "Could not detect original user desktop. Using: $TargetDir"
        }
    }
    else {
        # Expand environment variables if present in config path
        $TargetDir = [Environment]::ExpandEnvironmentVariables($TargetDir)
    }

    if (-not (Test-Path $TargetDir)) {
        try {
            New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        }
        catch {
            Write-AutoDerivaLog "ERROR" "Failed to create target directory: $TargetDir" "Red"
            return
        }
    }

    $CucoDest = Join-Path $TargetDir "CtoolGui.exe"
    $primaryUrl = 'https://cuco.inforlandia.pt/uagent/CtoolGui.exe'
    try {
        if ($Config.CucoDownloadUrl) { $primaryUrl = [string]$Config.CucoDownloadUrl }
    }
    catch {
        $primaryUrl = 'https://cuco.inforlandia.pt/uagent/CtoolGui.exe'
    }

    $fallbackUrl = $Config.BaseUrl + $Config.CucoBinaryPath

    Write-AutoDerivaLog "INFO" "Downloading Cuco utility to: $TargetDir" "Cyan"

    $downloaded = $false

    Write-AutoDerivaLog 'INFO' "Trying Cuco primary source: $primaryUrl" 'Gray'
    try {
        $okPrimary = Invoke-DownloadFile -Url $primaryUrl -OutputPath $CucoDest
        if ($okPrimary -and (Test-Path $CucoDest)) {
            $downloaded = $true
        }
    }
    catch {
        Write-Verbose "Primary Cuco download failed: $_"
    }

    if (-not $downloaded) {
        try {
            if (Test-Path -LiteralPath $CucoDest) { Remove-Item -LiteralPath $CucoDest -Force -ErrorAction SilentlyContinue }
        }
        catch {
            Write-Verbose "Failed to remove partial Cuco download before fallback: $_"
        }

        Write-AutoDerivaLog 'WARN' 'Primary Cuco source unavailable. Falling back to repo copy.' 'Yellow'
        Write-AutoDerivaLog 'INFO' "Trying Cuco fallback URL: $fallbackUrl" 'Gray'
        try {
            $okFallback = Invoke-DownloadFile -Url $fallbackUrl -OutputPath $CucoDest
            if ($okFallback -and (Test-Path $CucoDest)) {
                $downloaded = $true
            }
        }
        catch {
            Write-Verbose "Fallback Cuco download failed: $_"
        }
    }

    if ($downloaded) {
        $Script:Stats.CucoDownloaded++
        Write-AutoDerivaLog 'SUCCESS' 'Cuco utility downloaded successfully.' 'Green'
    }
    else {
        $Script:Stats.CucoDownloadFailed++
        Write-AutoDerivaLog 'ERROR' 'Failed to download Cuco from both primary and fallback sources.' 'Red'
    }
}

# .SYNOPSIS
#     Downloads all files from the manifest to the temp directory.
function Invoke-DownloadAllFile {
    param($TempDir)
    
    Write-Section "Download All Files"
    Write-AutoDerivaLog "INFO" "DownloadAllFiles is enabled. Fetching all files..." "Cyan"
    
    $ManifestUrl = $Config.BaseUrl + $Config.ManifestPath
    $FileManifest = Get-RemoteCsv -Url $ManifestUrl
    
    $FileList = @()
    foreach ($file in $FileManifest) {
        $remoteUrl = $Config.BaseUrl + $file.RelativePath
        $localPath = Join-Path $TempDir $file.RelativePath.Replace('/', '\')
        $expected = $null
        if ($file.PSObject.Properties.Name -contains 'Sha256') { $expected = $file.Sha256 }
        $FileList += @{ Url = $remoteUrl; OutputPath = $localPath; RelativePath = $file.RelativePath; ExpectedSha256 = $expected }
    }
    
    Invoke-ConcurrentDownload -FileList $FileList -MaxConcurrency $Config.MaxConcurrentDownloads
    Invoke-DownloadedFileHashVerification -FileList $FileList
    $Script:Stats.FilesDownloaded += $FileList.Count
    if ($Script:ExitAfterDownloadAll) {
        Write-AutoDerivaLog "INFO" "DownloadAllAndExit flag set. Exiting after download." "Cyan"
        Write-Progress -Id 1 -Completed
        return
    }
}

# .SYNOPSIS
#     Downloads multiple files concurrently using Runspaces.
# .PARAMETER FileList
#     Array of hashtables/objects with Url and OutputPath properties.
# .PARAMETER MaxConcurrency
#     Maximum number of concurrent downloads.
function Invoke-ConcurrentDownload {
    param($FileList, $MaxConcurrency = 6, [switch]$TestMode)

    if ($FileList.Count -eq 0) { return }

    Write-AutoDerivaLog "INFO" "Starting concurrent download of $( $FileList.Count ) files..." "Cyan"

    # TestMode: run sequentially in-process for deterministic testing/mocking.
    # IMPORTANT: Must not create runspaces or attempt real network operations.
    if ($TestMode) {
        $failedCount = 0
        $total = $FileList.Count
        $completed = 0

        foreach ($file in $FileList) {
            $ok = Invoke-DownloadFile -Url $file.Url -OutputPath $file.OutputPath
            if (-not $ok) {
                $failedCount++
                Write-AutoDerivaLog "WARN" "Failed to download: $($file.Url)" "Yellow"
            }

            $completed++
            $percent = [math]::Min(100, [int](($completed / $total) * 100))
            Write-Progress -Activity "Downloading Files (TestMode)" -Status "$completed / $total files" -PercentComplete $percent
        }
        Write-Progress -Activity "Downloading Files (TestMode)" -Status "Completed" -PercentComplete 100
        Write-Progress -Activity "Downloading Files (TestMode)" -Completed

        if ($total -gt 0) {
            $Script:Stats.FilesDownloadFailed += $failedCount
            $Script:Stats.FilesDownloaded += ($total - $failedCount)
        }

        return
    }

    # Test hook: allow substituting the entire concurrent download implementation for tests
    if ($Script:Test_InvokeConcurrentDownload) {
        return & $Script:Test_InvokeConcurrentDownload -FileList $FileList -MaxConcurrency $MaxConcurrency -TestMode:$TestMode
    }

    $RunspacePool = $null
    try {
        $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxConcurrency)
        $RunspacePool.Open()

        $ScriptBlock = {
            param($Url, $OutputPath, $MaxRetries)
            $ErrorActionPreference = "Stop"
            try {
                $dir = Split-Path $OutputPath -Parent
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            
                $retryCount = 0
                $success = $false
                $backoff = 2
            
                while (-not $success -and $retryCount -lt $MaxRetries) {
                    try {
                        # Use .NET WebClient for better compatibility in runspaces
                        $webClient = New-Object System.Net.WebClient
                        $webClient.DownloadFile($Url, $OutputPath)
                        $success = $true
                    }
                    catch {
                        $retryCount++
                        if ($retryCount -lt $MaxRetries) {
                            Start-Sleep -Seconds $backoff
                            $backoff = [math]::Min($backoff * 2, 60)
                        }
                    }
                }
            
                if ($success) { 
                    return @{ Success = $true; Url = $Url } 
                }
                else { 
                    return @{ Success = $false; Url = $Url; Error = "Max retries exceeded" } 
                }
            }
            catch {
                return @{ Success = $false; Url = $Url; Error = $_.ToString() }
            }
        }

        $Jobs = @()
        foreach ($file in $FileList) {
            $PS = [powershell]::Create().AddScript($ScriptBlock).AddArgument($file.Url).AddArgument($file.OutputPath).AddArgument(5)
            $PS.RunspacePool = $RunspacePool
            $Jobs += @{
                PS     = $PS
                Handle = $PS.BeginInvoke()
                File   = $file
            }
        }

        # Wait for completion
        $total = $Jobs.Count
        while (($Jobs | Where-Object { $_.Handle.IsCompleted }).Count -lt $total) {
            $completed = ($Jobs | Where-Object { $_.Handle.IsCompleted }).Count
            $percent = [math]::Min(100, [int](($completed / $total) * 100))
            Write-Progress -Activity "Downloading Files (Concurrent)" -Status "$completed / $total files" -PercentComplete $percent
            Start-Sleep -Milliseconds 200
        }
        Write-Progress -Activity "Downloading Files (Concurrent)" -Status "Completed" -PercentComplete 100
        Write-Progress -Activity "Downloading Files (Concurrent)" -Completed

        $failedCount = 0
        $total = $FileList.Count
        foreach ($job in $Jobs) {
            try {
                $result = $job.PS.EndInvoke($job.Handle)
                if (-not ($result -and $result.Success)) {
                    $failedCount++
                    $err = if ($result) { $result.Error } else { "Unknown error" }
                    Write-AutoDerivaLog "WARN" "Failed to download: $($job.File.Url) - $err" "Yellow"
                }
            }
            catch {
                $failedCount++
                Write-AutoDerivaLog "ERROR" "Job processing error: $_" "Red"
            }
            finally {
                $job.PS.Dispose()
            }
        }

        # Update global stats
        if ($total -gt 0) {
            $Script:Stats.FilesDownloadFailed += $failedCount
            $Script:Stats.FilesDownloaded += ($total - $failedCount)
        }
    }
    finally {
        if ($RunspacePool) {
            try { $RunspacePool.Close() } catch { Write-Verbose "Failed to close RunspacePool: $_" }
            try { $RunspacePool.Dispose() } catch { Write-Verbose "Failed to dispose RunspacePool: $_" }
        }
    }

} # end function Invoke-ConcurrentDownload

# ---------------------------------------------------------------------------
# 3b. MAIN - Execution Entry Point
# ---------------------------------------------------------------------------
function Main {
    # .SYNOPSIS
    #     Main entry point for the AutoDeriva installer.
    #
    # .DESCRIPTION
    #     Orchestrates the overall flow:
    #     - Optional Cuco download
    #     - Temp workspace creation and disk-space check
    #     - Optional download-all phase
    #     - Hardware detection and inventory fetch
    #     - Driver matching, download, and installation
    #     - Cleanup, statistics printing, optional Wi-Fi cleanup
    #     - Final exit wait (Enter/Ctrl+C) based on configuration
    #
    # .OUTPUTS
    #     None.
    $Script:HadFatalError = $false
    try {
        if ($Config.ShowBanner) {
            Write-AutoDerivaBanner
        }

        Test-PreFlight

        Invoke-PerformanceTuning

        if ($Script:ExitAfterWifiCleanup) {
            Write-Section 'Wi-Fi Cleanup'
            Clear-WifiProfile
            return
        }

        # Install Cuco
        Install-Cuco

        if ($Script:ExitAfterDownloadCuco) {
            Write-AutoDerivaLog "INFO" "DownloadCucoAndExit flag set. Exiting after Cuco download." "Cyan"

            $Script:Stats.EndTime = Get-Date
            $total = New-TimeSpan -Start $Script:Stats.StartTime -End $Script:Stats.EndTime

            Write-Section "Completion"
            Write-AutoDerivaLog "DONE" "AutoDeriva process completed in $(Format-AutoDerivaDuration -Duration $total)." "Green"

            Write-Section "Statistics"
            Write-AutoDerivaStat -Label 'Cuco Downloaded' -Value $Script:Stats.CucoDownloaded -Color 'Green'
            Write-AutoDerivaStat -Label 'Cuco Failed' -Value $Script:Stats.CucoDownloadFailed -Color 'Red'
            Write-AutoDerivaStat -Label 'Cuco Skipped' -Value $Script:Stats.CucoSkipped -Color 'Gray'

            # Finalize and print section timings
            try {
                Complete-AutoDerivaSectionTiming -Now $Script:Stats.EndTime
                $Script:CurrentSectionTitle = $null
                $Script:CurrentSectionStart = $null
                if ($Script:SectionTimings.Count -gt 0) {
                    Write-Section 'Section Timings' -NoTiming
                    foreach ($rec in $Script:SectionTimings) {
                        if (-not $rec) { continue }
                        $label = [string]$rec.Title
                        $elapsed = [TimeSpan]$rec.Elapsed
                        if ($label -eq 'Wi-Fi Cleanup') { continue }
                        if ($elapsed.TotalSeconds -lt 1) { continue }
                        Write-AutoDerivaStatText -Label $label -Value (Format-AutoDerivaDuration -Duration $elapsed) -Color 'Gray'
                    }
                }
            }
            catch {
                Write-Verbose "Failed to print section timings: $_"
            }
            return
        }

        # Create Temp Directory
        $TempDir = Join-Path $env:TEMP "AutoDeriva_$(Get-Random)"
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
        Write-AutoDerivaLog "INFO" "Temporary workspace: $TempDir" "Gray"

        # Check Disk Space
        if ($Config.CheckDiskSpace -and -not (Test-DiskSpace -Path $TempDir)) {
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

        # Compute unknown driver count after install attempt.
        # This can be slow on some systems; only rescan when we actually installed drivers.
        if ($env:AUTODERIVA_TEST -ne '1') {
            if ($Script:Stats.DriversInstalled -gt 0) {
                $Script:Stats.UnknownDriversAfterInstall = Get-UnknownDriverDeviceCount
            }
            else {
                Write-AutoDerivaLog 'INFO' 'Skipping post-install device rescan (no drivers were installed).' 'Gray'
            }
        }

        # Cleanup
        Write-Section "Cleanup"
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force
            Write-AutoDerivaLog "INFO" "Temporary files removed." "Green"
        }

        # Optional Wi-Fi cleanup at end (default enabled)
        Write-Section 'Wi-Fi Cleanup'
        Clear-WifiProfile

        $Script:Stats.EndTime = Get-Date
        $total = New-TimeSpan -Start $Script:Stats.StartTime -End $Script:Stats.EndTime

        Write-Section "Completion"
        Write-AutoDerivaLog "DONE" "AutoDeriva process completed in $(Format-AutoDerivaDuration -Duration $total)." "Green"
        if ($LogFilePath) {
            Write-AutoDerivaLog "INFO" "Log saved to: $LogFilePath" "Gray"
        }
        
        Write-Section "Statistics"
        Write-AutoDerivaStat -Label 'Cuco Downloaded' -Value $Script:Stats.CucoDownloaded -Color 'Green'
        Write-AutoDerivaStat -Label 'Cuco Failed' -Value $Script:Stats.CucoDownloadFailed -Color 'Red'
        Write-AutoDerivaStat -Label 'Cuco Skipped' -Value $Script:Stats.CucoSkipped -Color 'Gray'
        Write-AutoDerivaStat -Label 'Hardware IDs Scanned' -Value $Script:Stats.DriversScanned -Color 'Cyan'
        Write-AutoDerivaStat -Label 'Drivers Matched' -Value $Script:Stats.DriversMatched -Color 'Cyan'
        Write-AutoDerivaStat -Label 'Files Downloaded' -Value $Script:Stats.FilesDownloaded -Color 'Cyan'
        Write-AutoDerivaStat -Label 'Files Failed' -Value $Script:Stats.FilesDownloadFailed -Color 'Yellow'
        Write-AutoDerivaStat -Label 'Drivers Skipped' -Value $Script:Stats.DriversSkipped -Color 'Gray'
        Write-AutoDerivaStat -Label 'Drivers Present' -Value $Script:Stats.DriversAlreadyPresent -Color 'Gray'
        Write-AutoDerivaStat -Label 'Drivers Installed' -Value $Script:Stats.DriversInstalled -Color 'Green'
        Write-AutoDerivaStat -Label 'Drivers Failed' -Value $Script:Stats.DriversFailed -Color 'Red'
        Write-AutoDerivaStat -Label 'Unknown Drivers' -Value $Script:Stats.UnknownDriversAfterInstall -Color 'Yellow'
        Write-AutoDerivaStat -Label 'Reboots Required' -Value $Script:Stats.RebootsRequired -Color 'Yellow'

        # Finalize and print section timings
        try {
            Complete-AutoDerivaSectionTiming -Now $Script:Stats.EndTime
            $Script:CurrentSectionTitle = $null
            $Script:CurrentSectionStart = $null
            if ($Script:SectionTimings.Count -gt 0) {
                Write-Section 'Section Timings' -NoTiming
                foreach ($rec in $Script:SectionTimings) {
                    if (-not $rec) { continue }
                    $label = [string]$rec.Title
                    $elapsed = [TimeSpan]$rec.Elapsed
                    if ($label -eq 'Wi-Fi Cleanup') { continue }
                    if ($elapsed.TotalSeconds -lt 1) { continue }
                    Write-AutoDerivaStatText -Label $label -Value (Format-AutoDerivaDuration -Duration $elapsed) -Color 'Gray'
                }
            }
        }
        catch {
            Write-Verbose "Failed to print section timings: $_"
        }

        if ($InstallResults.Count -gt 0) {
            Write-Section "Detailed Summary"
            $InstallResults | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White
            if ($LogFilePath) {
                $InstallResults | Format-Table -AutoSize | Out-String | Add-Content -Path $LogFilePath
            }
        }

    }
    catch {
        $Script:HadFatalError = $true
        Write-AutoDerivaLog "FATAL" "An unexpected error occurred: $_" "Red"
        Write-AutoDerivaLog "FATAL" $($_.ScriptStackTrace) "Red"
    }
    finally {
        Write-Host "`n"
        # Avoid interactive prompt during automated tests; allow Ctrl+C as alternative to Enter.
        $autoExit = $false
        try { $autoExit = [bool]$Config.AutoExitWithoutConfirmation } catch { $autoExit = $false }
        $forceWait = ($env:AUTODERIVA_NOEXIT -eq '1')
        if ($Script:HadFatalError) {
            # If we hit a fatal error in an interactive ConsoleHost, keep the window open
            # so the user can read the error, even if AutoExitWithoutConfirmation is set.
            if (Test-AutoDerivaPromptAvailable) {
                $autoExit = $false
                $forceWait = $true
            }
        }
        Wait-AutoDerivaExit -AutoExit:$autoExit -Force:($forceWait -and $Script:HadFatalError)
    }
}

# ---------------------------------------------------------------------------
# 4. EXECUTION
# ---------------------------------------------------------------------------

if ($PSBoundParameters.ContainsKey('ExportUnknownDevicesCsv') -and $ExportUnknownDevicesCsv) {
    Export-AutoDerivaUnknownDevicesCsv -Path $ExportUnknownDevicesCsv
    return
}

if ($env:AUTODERIVA_TEST -eq '1') {
    Write-Verbose "AUTODERIVA_TEST is set - skipping automatic Main() execution (test mode)."
}
else {
    Main
}


