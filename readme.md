# AutoDeriva

[![CI](https://img.shields.io/github/actions/workflow/status/supermarsx/autoderiva/ci.yml?branch=main&style=flat-square)](https://github.com/supermarsx/autoderiva/actions/workflows/ci.yml)
![GitHub stars](https://img.shields.io/github/stars/supermarsx/autoderiva?style=flat-square)
![GitHub forks](https://img.shields.io/github/forks/supermarsx/autoderiva?style=flat-square)
![GitHub watchers](https://img.shields.io/github/watchers/supermarsx/autoderiva?style=flat-square)
![Repo Size](https://img.shields.io/github/repo-size/supermarsx/autoderiva?style=flat-square)
![Driver Count](https://img.shields.io/badge/Drivers-163+-blue?style=flat-square)
[![Documentation](https://img.shields.io/badge/Docs-Configuration-blue?style=flat-square)](docs/configuration.md)
[![Download BAT](https://img.shields.io/badge/Download-Install--AutoDeriva.bat-blue?style=flat-square)](https://github.com/supermarsx/autoderiva/releases/latest/download/Install-AutoDeriva.bat)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](license.md)


**AutoDeriva** is a powerful, automated system setup and driver installer designed for remote and hybrid environments. It intelligently scans your system's hardware, matches it against a remote inventory of drivers, and automatically downloads and installs the necessary components.

## 🚀 Quick Start

Fastest (PowerShell one-liner):

```powershell
irm https://raw.githubusercontent.com/supermarsx/autoderiva/main/scripts/Install-AutoDeriva.ps1 | iex
```

Recommended (Windows portable batch launcher that downloads + runs the installer and forwards arguments):

```bat
curl -L -o Install-AutoDeriva.bat https://github.com/supermarsx/autoderiva/releases/latest/download/Install-AutoDeriva.bat
Install-AutoDeriva.bat
```

Useful quick commands:

```bat
Install-AutoDeriva.bat -Help
Install-AutoDeriva.bat -ShowConfig
Install-AutoDeriva.bat -DryRun
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

## ✨ Features

*   **Smart driver matching**: matches by Hardware IDs; installs with `pnputil`.
*   **Safe-by-default scanning**: defaults to scanning only devices missing drivers (PnP ProblemCode `28`).
*   **Resilient downloads**: retry + backoff and a concurrency-safe downloader.
*   **Optional integrity checks**: verify downloaded files using SHA256 from the manifest (disabled by default).
*   **Layered configuration**: built-in defaults → `config.defaults.json` → `config.json` → optional remote overrides → CLI.
*   **Wi‑Fi cleanup options**: conservative default (delete a single profile name) and a Wi‑Fi-only mode.
*   **Cleaner output**: Statistics hide zero counters by default (configurable).
*   **Test-friendly**: set `AUTODERIVA_TEST=1` to skip elevation and destructive prompts in CI/tests.

## 🎚️ Configuration

AutoDeriva loads configuration in layers (later overrides earlier):

1) Built-in defaults (in the script)
2) `config.defaults.json` (local if present, otherwise fetched from the repo)
3) `config.json` (optional local overrides)
4) Remote config overrides (optional):
    - `RemoteConfigUrl` in config
    - or `-ConfigUrl <url>` on the CLI (takes precedence)
5) CLI flags (highest priority)

You can keep `config.json` minimal—only include keys you want to change.

Example minimal `config.json` (override only what you need):

```json
{
    "RemoteConfigUrl": null,
    "MaxConcurrentDownloads": 2,
    "ScanOnlyMissingDrivers": true,
    "ClearWifiProfiles": true,
    "WifiCleanupMode": "SingleOnly",
    "WifiProfileNameToDelete": "Null",
    "ShowOnlyNonZeroStats": true
}
```

For the full key reference (types, defaults, and notes), see `docs/configuration.md`.

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
| `CucoPrimaryUrl` | string | `https://cuco.inforlandia.pt/uagent/CtoolGui.exe` | Primary URL to download the Cuco binary from. |
| `CucoSecondaryUrl` | string/null | `null` | Secondary URL for Cuco. When `null`, AutoDeriva uses `BaseUrl + CucoBinaryPath` as the secondary source. |
| `CucoDownloadUrl` | string | `https://cuco.inforlandia.pt/uagent/CtoolGui.exe` | Legacy alias for `CucoPrimaryUrl` (backward compatibility). |
| `CucoBinaryPath` | string | `cuco/CtoolGui.exe` | Relative path (from `BaseUrl`) used to derive the default secondary URL when `CucoSecondaryUrl` is `null`. |
| `DownloadCuco` | boolean | `true` | If `true`, the Cuco utility is downloaded to the target directory. |
| `CucoTargetDir` | string | `Desktop` | Where to place the Cuco binary. `Desktop` resolves to the original user's Desktop folder when possible. |
| `AskBeforeDownloadCuco` | boolean | `false` | When `true`, asks for confirmation before downloading Cuco. Default is `false` (no prompt). |
| `CucoExistingFilePolicy` | string | `Skip` | What to do if `CtoolGui.exe` already exists in `CucoTargetDir`: `Skip` (default) or `Overwrite`. |
| `MaxRetries` | integer | `5` | Number of retries the downloader will attempt on transient failures. |
| `MaxBackoffSeconds` | integer | `60` | Maximum backoff time (in seconds) between retry attempts. |
| `MinDiskSpaceMB` | integer | `3072` | Minimum free disk space required (in MB) for temporary downloads. Checked before the main download phase (unless disabled). |
| `CheckDiskSpace` | boolean | `true` | Enable/disable the disk space check (if `false`, the check is skipped). Default is `true`. |
| `MaxConcurrentDownloads` | integer | `6` | Maximum number of parallel download threads used by the Runspace-based downloader. Lower this on low-resource systems. |
| `SingleDownloadMode` | boolean | `false` | When `true`, forces `MaxConcurrentDownloads` to `1` and effectively disables concurrency. Default is `false`. |
| `VerifyFileHashes` | boolean | `false` | If `true`, verifies downloaded files using the `Sha256` column from the file manifest CSV. Disabled by default. |
| `DeleteFilesOnHashMismatch` | boolean | `false` | If `true`, deletes a downloaded file when its SHA256 mismatches. Default is to warn and keep the file. |
| `HashMismatchPolicy` | string | `Continue` | What to do when a file hash mismatches (when `VerifyFileHashes` is enabled): `Continue` (default; install anyway), `SkipDriver` (skip installing affected drivers), or `Abort` (stop driver installation phase). |
| `HashVerifyMode` | string | `Parallel` | Hash verification mode when `VerifyFileHashes` is enabled: `Parallel` or `Single`. |
| `HashVerifyMaxConcurrency` | integer | `5` | Max number of files to hash in parallel when `HashVerifyMode` is `Parallel`. |
| `ScanOnlyMissingDrivers` | boolean | `true` | When `true`, only scans devices that are missing drivers (PnP ProblemCode `28`) and ignores hardware IDs from devices with working drivers. Default is `true`. |
| `ClearWifiProfiles` | boolean | `true` | Master switch for Wi‑Fi profile cleanup at the end of the run. Default is `true`. |
| `AskBeforeClearingWifiProfiles` | boolean | `false` | When `true`, asks for confirmation before deleting saved Wi‑Fi profiles. Default is `false` (no prompt). |
| `WifiCleanupMode` | string | `SingleOnly` | Wi‑Fi profile cleanup mode. Supported values: `SingleOnly`, `All`, `None`. Default is `SingleOnly` (delete only the profile name below). |
| `WifiProfileNameToDelete` | string | `Null` | Wi‑Fi profile name used by `WifiCleanupMode: SingleOnly`. Default is `Null`. |
| `AutoExitWithoutConfirmation` | boolean | `false` | When `true`, exits without waiting for confirmation at the end. Default is `false` (waits for Enter or Ctrl+C). |
| `ShowOnlyNonZeroStats` | boolean | `true` | When `true`, the Statistics section only prints counters greater than `0`. Default is `true`. |

## 🧭 CLI Options

You can pass arguments either to `Install-AutoDeriva.ps1` or to `Install-AutoDeriva.bat` (the BAT forwards args to the script).

Run `-Help` for the authoritative list. Highlights:

Configuration:

* `-ConfigPath <path>` — Use a custom config file as overrides.
* `-ConfigUrl <url>` — Load JSON config overrides from a URL (overrides `RemoteConfigUrl`).
* `-ShowConfig` — Print the effective configuration and exit (also used by tests/tools).

Logging:

* `-EnableLogging` — Enable logging.
* `-CleanLogs` — Delete ALL `autoderiva-*.log` files in the logs folder.
* `-LogRetentionDays <n>` — Auto-delete logs older than `<n>` days.
* `-MaxLogFiles <n>` — Keep only the newest `<n>` logs.
* `-NoLogCleanup` — Disable automatic log cleanup.

Download modes:

* `-DownloadAllFiles` — Download all files from the manifest.
* `-DownloadAllAndExit` (alias: `-DownloadOnly`) — Download all files then exit.
* `-SingleDownloadMode` — Force single-threaded downloads.
* `-MaxConcurrentDownloads <n>` — Control number of parallel downloads.
* `-NoDiskSpaceCheck` — Skip the pre-flight disk space check.
* `-VerifyFileHashes <true|false>` — Enable/disable SHA256 verification using the manifest.
* `-DeleteFilesOnHashMismatch <true|false>` — Delete a file when it mismatches (default is warn+keep).
* `-HashMismatchPolicy <Continue|SkipDriver|Abort>` — Continue installing, skip affected drivers, or abort driver install phase.
* `-HashVerifyMode <Parallel|Single>` — Hash verification mode when enabled.
* `-HashVerifyMaxConcurrency <n>` — Max parallel hash workers when mode is `Parallel`.

Cuco:

* `-DownloadCuco` — Download the Cuco utility.
* `-DownloadCucoAndExit` (alias: `-CucoOnly`) — Download Cuco then exit.
* `-CucoTargetDir <path>` — Override Cuco output directory.
* `-AskBeforeDownloadCuco` / `-NoAskBeforeDownloadCuco` — Toggle prompt.

Driver scan behavior:

* `-ScanOnlyMissingDrivers` — Only scan devices missing drivers.
* `-ScanAllDevices` — Scan all present devices.

Wi‑Fi cleanup:

* `-ClearWifiAndExit` (aliases: `-WifiCleanupAndExit`, `-WifiOnly`) — Only run Wi‑Fi cleanup and exit.
* `-ClearWifiProfiles` — Enable Wi‑Fi cleanup at end.
* `-NoWifiCleanup` (alias: `-NoClearWifiProfiles`) — Disable Wi‑Fi cleanup at end.
* `-WifiCleanupMode <SingleOnly|All|None>` — Cleanup mode.
* `-WifiProfileNameToDelete <name>` (aliases: `-WifiName`, `-WifiProfileName`) — Profile name used by `SingleOnly`.
* `-AskBeforeClearingWifiProfiles` / `-NoAskBeforeClearingWifiProfiles` — Toggle prompt.

End-of-run behavior:

* `-AutoExitWithoutConfirmation` — Exit without waiting at end.
* `-RequireExitConfirmation` — Force waiting at end.

Output:

* `-ShowOnlyNonZeroStats` — Only show counters above 0.
* `-ShowAllStats` — Show all counters including zeros.

Safety/testing:

* `-DryRun` — Dry run (no downloads or installs).
* `AUTODERIVA_TEST=1` — Environment variable used by tests/CI to skip elevation and interactive behaviors.

Example:

```powershell
.\Install-AutoDeriva.ps1 -EnableLogging -MaxConcurrentDownloads 2
```

Enable hash verification (keep files by default; skip affected drivers on mismatch):

```powershell
.\Install-AutoDeriva.ps1 -VerifyFileHashes $true -HashMismatchPolicy SkipDriver
```

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

## 📜 Scripts

*   \Install-AutoDeriva.ps1\: The main installer script.
*   \startup-script.ps1\: A lightweight bootstrapper to launch the installer.
*   \Get-DriverInventory.ps1\: (Dev) Generates the driver inventory CSV.
*   \Get-DriverFileManifest.ps1\: (Dev) Generates the file manifest for the repository.
*   \dev-scripts\: Contains build, lint, and test scripts for development.

## 📄 License

This project is distributed under the MIT License. See `license.md` for the full license text.
