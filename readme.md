# AutoDeriva

[![CI](https://img.shields.io/github/actions/workflow/status/supermarsx/autoderiva/ci.yml?branch=main&style=flat-square)](https://github.com/supermarsx/autoderiva/actions/workflows/ci.yml)
![GitHub stars](https://img.shields.io/github/stars/supermarsx/autoderiva?style=flat-square)
![GitHub forks](https://img.shields.io/github/forks/supermarsx/autoderiva?style=flat-square)
![GitHub watchers](https://img.shields.io/github/watchers/supermarsx/autoderiva?style=flat-square)
![Repo Size](https://img.shields.io/github/repo-size/supermarsx/autoderiva?style=flat-square)
![Driver Count](https://img.shields.io/badge/Drivers-163+-blue?style=flat-square)
[![Documentation](https://img.shields.io/badge/Docs-Configuration-blue?style=flat-square)](docs/configuration.md)
[![Download BAT](https://img.shields.io/badge/Download-Install--AutoDeriva.bat-blue?style=flat-square)](https://raw.githubusercontent.com/supermarsx/autoderiva/refs/heads/main/Install-AutoDeriva.bat)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](license.md)


**AutoDeriva** is a powerful, automated system setup and driver installer designed for remote and hybrid environments. It intelligently scans your system's hardware, matches it against a remote inventory of drivers, and automatically downloads and installs the necessary components.

## 🚀 Quick Start

Run the installer directly from PowerShell with this one-liner:

```powershell
irm https://raw.githubusercontent.com/supermarsx/autoderiva/main/scripts/Install-AutoDeriva.ps1 | iex
```

Windows portable batch launcher (downloads + runs the installer):

```bat
curl -L -o Install-AutoDeriva.bat https://raw.githubusercontent.com/supermarsx/autoderiva/main/Install-AutoDeriva.bat
Install-AutoDeriva.bat
```

### Download only (save the script locally)

If you just want to download the installer script (similar to using `curl`), here are a few cross-platform options:

PowerShell (Windows PowerShell / PowerShell 7+):

```powershell
# Windows PowerShell (use -UseBasicParsing on older PowerShell 5.1 hosts)
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/scripts/Install-AutoDeriva.ps1' -OutFile 'Install-AutoDeriva.ps1' -UseBasicParsing

# PowerShell 7+ (pwsh) - Use native behaviour
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/scripts/Install-AutoDeriva.ps1' -OutFile 'Install-AutoDeriva.ps1'
```

After downloading, run the script with appropriate execution policy privileges:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-AutoDeriva.ps1
# or (PowerShell 7+)
pwsh -File ./Install-AutoDeriva.ps1
```

## 🎚️ Configuration file

AutoDeriva loads configuration in layers (later overrides earlier):

1) Built-in defaults (in the script)
2) `config.defaults.json` (local if present, otherwise fetched from the repo)
3) `config.json` (optional local overrides)
4) Remote config overrides (optional):
    - `RemoteConfigUrl` in config
    - or `-ConfigUrl <url>` on the CLI (takes precedence)
5) CLI flags (highest priority)

You can keep `config.json` minimal—only include keys you want to change.

Example `config.json`:

```json
{
    "MaxConcurrentDownloads": 2,
    "SingleDownloadMode": false,
    "ScanOnlyMissingDrivers": true,
    "WifiCleanupMode": "SingleOnly",
    "WifiProfileNameToDelete": "Null"
}
```

For a longer explanation and troubleshooting notes, see `docs/configuration.md`.

### Configuration keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `BaseUrl` | string | `https://raw.githubusercontent.com/supermarsx/autoderiva/main/` | Base URL used to fetch manifests and driver files. Change this to point to a different host if needed. |
| `InventoryPath` | string | `exports/driver_inventory.csv` | Path (relative to `BaseUrl`) to the driver inventory CSV. |
| `ManifestPath` | string | `exports/driver_file_manifest.csv` | Path (relative to `BaseUrl`) to the file manifest CSV. |
| `RemoteConfigUrl` | string/null | `null` | Optional URL to a JSON config file whose properties are applied as overrides after `config.json`. Useful for centrally managed configs. |
| `EnableLogging` | boolean | `true` | Enable writing a runtime log file. Log files are written under `logs/` when enabled. |
| `LogLevel` | string | `INFO` | The logging verbosity. Supported values: `DEBUG`, `INFO`, `WARN`, `ERROR`. |
| `AutoCleanupLogs` | boolean | `true` | If `true`, automatically deletes old log files using the retention rules below. |
| `LogRetentionDays` | integer | `10` | Delete log files older than this many days. Set to `0` to disable age-based cleanup. |
| `MaxLogFiles` | integer | `15` | Keep at most this many log files (newest kept). Set to `0` to disable count-based cleanup. |
| `DownloadAllFiles` | boolean | `false` | If `true`, downloads *all* files from the manifest (useful for offline scenarios). |
| `CucoBinaryPath` | string | `cuco/CtoolGui.exe` | Relative path (from `BaseUrl`) to the Cuco utility binary. |
| `DownloadCuco` | boolean | `true` | If `true`, the Cuco utility is downloaded to the target directory. |
| `CucoTargetDir` | string | `Desktop` | Where to place the Cuco binary. `Desktop` resolves to the original user's Desktop folder when possible. |
| `AskBeforeDownloadCuco` | boolean | `false` | When `true`, asks for confirmation before downloading Cuco. Default is `false` (no prompt). |
| `MaxRetries` | integer | `5` | Number of retries the downloader will attempt on transient failures. |
| `MaxBackoffSeconds` | integer | `60` | Maximum backoff time (in seconds) between retry attempts. |
| `MinDiskSpaceMB` | integer | `3072` | Minimum free disk space required (in MB) for temporary downloads. Checked before the main download phase (unless disabled). |
| `CheckDiskSpace` | boolean | `true` | Enable/disable the disk space check (if `false`, the check is skipped). Default is `true`. |
| `MaxConcurrentDownloads` | integer | `6` | Maximum number of parallel download threads used by the Runspace-based downloader. Lower this on low-resource systems. |
| `SingleDownloadMode` | boolean | `false` | When `true`, forces `MaxConcurrentDownloads` to `1` and effectively disables concurrency. Default is `false`. |
| `ScanOnlyMissingDrivers` | boolean | `true` | When `true`, only scans devices that are missing drivers (PnP ProblemCode `28`) and ignores hardware IDs from devices with working drivers. Default is `true`. |
| `ClearWifiProfiles` | boolean | `true` | Master switch for Wi‑Fi profile cleanup at the end of the run. Default is `true`. |
| `AskBeforeClearingWifiProfiles` | boolean | `false` | When `true`, asks for confirmation before deleting saved Wi‑Fi profiles. Default is `false` (no prompt). |
| `WifiCleanupMode` | string | `SingleOnly` | Wi‑Fi profile cleanup mode. Supported values: `SingleOnly`, `All`, `None`. Default is `SingleOnly` (delete only the profile name below). |
| `WifiProfileNameToDelete` | string | `Null` | Wi‑Fi profile name used by `WifiCleanupMode: SingleOnly`. Default is `Null`. |
| `AutoExitWithoutConfirmation` | boolean | `false` | When `true`, exits without waiting for confirmation at the end. Default is `false` (waits for Enter or Ctrl+C). |
| `ShowOnlyNonZeroStats` | boolean | `true` | When `true`, the Statistics section only prints counters greater than `0`. Default is `true`. |

## 🧭 CLI Options

You can pass script-level arguments when running `Install-AutoDeriva.ps1` directly. Common flags:

* `-ConfigPath <path>` — Path to a custom `config.json` to override defaults.
* `-ConfigUrl <url>` — Load JSON config overrides from a URL (also configurable via `RemoteConfigUrl` in `config.json`).
* `-EnableLogging` — Enable logging (overrides config file setting).
* `-CleanLogs` — Delete all `autoderiva-*.log` files in the `logs/` folder.
* `-LogRetentionDays <n>` — Auto-delete logs older than `<n>` days (overrides config).
* `-MaxLogFiles <n>` — Keep only the newest `<n>` logs (overrides config).
* `-NoLogCleanup` — Disable automatic log cleanup (retention/max-files).
* `-DownloadAllFiles` — Download all files from the manifest (overrides config file setting).
* `-DownloadAllAndExit` (alias: `-DownloadOnly`) — Download all files from the manifest, then exit immediately (no installs). Useful to mirror `DownloadAllFiles` but only fetch files.
* `-DownloadCuco` — Enable downloading the Cuco utility.
* `-DownloadCucoAndExit` (alias: `-CucoOnly`) — Download Cuco only, print stats, then exit.
* `-CucoTargetDir <path>` — Override where the Cuco utility will be written (defaults to `Desktop`).
* `-SingleDownloadMode` — Force single-threaded downloads (equivalent to setting `SingleDownloadMode: true` in the config).
* `-MaxConcurrentDownloads <n>` — Control number of parallel downloads (overrides `MaxConcurrentDownloads`).
* `-NoDiskSpaceCheck` — Skip the pre-flight disk space check.
* `-ShowConfig` — Print the effective configuration and exit.
* `-DryRun` — Perform a dry run (no downloads or installs performed; useful for testing).
* `-Help` or `-?` — Show usage/help message and exit.

Example:

```powershell
.\Install-AutoDeriva.ps1 -EnableLogging -MaxConcurrentDownloads 2
```

## ✨ Features

*   **Smart Driver Matching**: Uses Hardware IDs to identify and install only the drivers your system needs.
*   **Remote Inventory**: Fetches driver metadata and files from a remote repository, eliminating the need for a massive local driver store.
*   **Auto-Elevation**: Automatically requests administrative privileges to ensure seamless installation.
*   **Resilient Downloads**: Includes retry logic and exponential backoff for reliable file fetching.
*   **Disk Space Checks**: Verifies sufficient disk space before starting downloads.
*   **Detailed Logging**: Keeps a comprehensive log of all actions for troubleshooting (stored under `logs/`).
*   **Log Retention**: Optional automatic cleanup of old logs by age and max file count.
*   **Cuco Utility Integration**: Optionally downloads the Cuco utility (\CtoolGui.exe\) to the user's desktop.
*   **Beautiful TUI**: Features a colorful, text-based user interface with progress bars and ASCII art.

## 💻 Supported Models

AutoDeriva currently supports drivers for the following models (and more):

*   **GW1-W149**
*   **HP 240 G8**
*   **Leap T304 (SF20PA6W)**

## 📦 Included Drivers

The repository hosts a wide range of drivers, including but not limited to:

*   **Audio**: Realtek, Intel Smart Sound, Everest Semiconductor
*   **Display**: Intel UHD Graphics
*   **Network**: Intel Wireless AC, Bluetooth
*   **System**: Intel Chipset, Dynamic Tuning, Management Engine, Serial IO
*   **Input**: HID Event Filters, Touchpad drivers
*   **Storage**: Intel Rapid Storage, SD Card Readers

## 🛠️ Installation Method

1.  **Configuration**: The script loads settings from \config.defaults.json\ (remote or local) and overrides them with \config.json\ if present.
2.  **Inventory Fetch**: It downloads the \driver_inventory.csv\ to understand what drivers are available.
3.  **Hardware Scan**: It scans your local machine for active Hardware IDs.
4.  **Matching**: It compares your hardware against the inventory to find matches.
5.  **Download & Install**:
    *   It downloads the specific INF files and associated binaries to a temporary directory.
    *   It uses \PnPUtil\ to install the drivers into the Windows Driver Store.
6.  **Cleanup**: Temporary files are removed after installation.

## ⚙️ Configuration

Configuration options are documented in `docs/configuration.md`. The script loads defaults from `config.defaults.json` (remote or local) and applies overrides from `config.json` when present. See the docs for key descriptions, types, and examples.

Note: log files are written to the `logs/` folder (gitignored). Cleanup behavior is controlled via `AutoCleanupLogs`, `LogRetentionDays`, and `MaxLogFiles`.

## 🔧 Cuco Utility

AutoDeriva can automatically download the **Cuco Utility** (\CtoolGui.exe\) to your Desktop. This behavior is configurable:

*   **Enable/Disable**: Set \"DownloadCuco": false\ in your config to disable.
*   **Target Directory**: Configure \"CucoTargetDir"\ to specify a custom download location (defaults to "Desktop").

## 📜 Scripts

*   \Install-AutoDeriva.ps1\: The main installer script.
*   \startup-script.ps1\: A lightweight bootstrapper to launch the installer.
*   \Get-DriverInventory.ps1\: (Dev) Generates the driver inventory CSV.
*   \Get-DriverFileManifest.ps1\: (Dev) Generates the file manifest for the repository.
*   \dev-scripts\: Contains build, lint, and test scripts for development.

## 📄 License

This project is distributed under the MIT License. See `LICENSE.md` for the full license text.
