# AutoDeriva

[![CI](https://img.shields.io/github/actions/workflow/status/supermarsx/autoderiva/ci.yml?branch=main&style=flat-square)](https://github.com/supermarsx/autoderiva/actions/workflows/ci.yml)
![GitHub stars](https://img.shields.io/github/stars/supermarsx/autoderiva?style=flat-square)
![GitHub forks](https://img.shields.io/github/forks/supermarsx/autoderiva?style=flat-square)
![GitHub watchers](https://img.shields.io/github/watchers/supermarsx/autoderiva?style=flat-square)
![Repo Size](https://img.shields.io/github/repo-size/supermarsx/autoderiva?style=flat-square)
![Driver Count](https://img.shields.io/badge/Drivers-163+-blue?style=flat-square)
[![Documentation](https://img.shields.io/badge/Docs-Configuration-blue?style=flat-square)](docs/configuration.md) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE.md)


**AutoDeriva** is a powerful, automated system setup and driver installer designed for remote and hybrid environments. It intelligently scans your system's hardware, matches it against a remote inventory of drivers, and automatically downloads and installs the necessary components.

## 🚀 Quick Start

Run the installer directly from PowerShell with this one-liner:

```powershell
irm https://raw.githubusercontent.com/supermarsx/autoderiva/main/scripts/Install-AutoDeriva.ps1 | iex
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

See `docs/configuration.md` for configuration options and examples.

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

Configuration options are documented in `docs/CONFIGURATION.md`. The script loads defaults from `config.defaults.json` (remote or local) and applies overrides from `config.json` when present. See the docs for key descriptions, types, and examples.

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
