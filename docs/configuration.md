# AutoDeriva Configuration Reference

This document lists all configuration keys supported by AutoDeriva, their types, default values, and descriptions.

Where to configure

- Default values are stored in `config.defaults.json` in the repository root.
- Local overrides can be placed in `config.json` (also in repository root). If a property exists in `config.json`, it will override the corresponding default.
- If `config.defaults.json` is not present locally, the script attempts to fetch remote defaults from the GitHub repository.

Example `config.json`:

```json
{
    "BaseUrl": "https://raw.githubusercontent.com/supermarsx/autoderiva/main/",
    "DownloadAllFiles": false,
    "CheckDiskSpace": true,
    "SingleDownloadMode": false,
    "MaxConcurrentDownloads": 6
}
```

Configuration keys

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
| `AskBeforeDownloadCuco` | boolean | `false` | When `true`, asks for confirmation before downloading Cuco. Default is `false` (no prompt). |
| `CucoTargetDir` | string | `Desktop` | Where to place the Cuco binary. `Desktop` resolves to the original user's Desktop folder when possible. |
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

Notes & behavior

- `SingleDownloadMode` is a convenience toggle that forces the downloader to operate one file at a time. This is useful on systems where concurrent downloads cause problems (e.g., due to throttling or instability).
- `CheckDiskSpace` is run before creating the temporary workspace; set it to `false` if you have special storage arrangements or don't want the script to perform the free-space check.
- To override defaults, create a `config.json` containing only the keys you want to change. Example above shows a minimal override.
- `ScanOnlyMissingDrivers` uses the PnP ProblemCode to identify devices missing drivers. On some systems/hosts, determining the ProblemCode may be limited; if so, the scan may find fewer IDs.
- Wi‑Fi cleanup runs at the end of the script so it does not interfere with driver downloads during the run.
- Default Wi‑Fi behavior is conservative: `WifiCleanupMode: SingleOnly` with `WifiProfileNameToDelete: Null`.

Troubleshooting tips

- If downloads fail due to connection issues or throttling, try reducing `MaxConcurrentDownloads` or enable `SingleDownloadMode`.
- When enabling logging, inspect `logs/autoderiva-<timestamp>.log` for detailed error messages.
- If you see too many logs accumulate, adjust `LogRetentionDays` and/or `MaxLogFiles`, or disable cleanup entirely with `AutoCleanupLogs: false`.

CLI Overrides

Many of the configuration options can also be supplied as CLI flags when invoking `Install-AutoDeriva.ps1`. These flags will override values from `config.defaults.json` and `config.json`:

* `-ConfigPath <path>` — Load the specified JSON file as additional overrides.
* `-ConfigUrl <url>` — Load JSON config overrides from a URL (overrides `RemoteConfigUrl` when provided).
* `-EnableLogging` — Enable logging regardless of config file.
* `-CleanLogs` — Delete all `autoderiva-*.log` files in the `logs/` folder.
* `-LogRetentionDays <n>` — Override `LogRetentionDays`.
* `-MaxLogFiles <n>` — Override `MaxLogFiles`.
* `-NoLogCleanup` — Disable automatic log cleanup regardless of config.
* `-DownloadAllFiles` — Force download-all behavior.
* `-DownloadAllAndExit` / `-DownloadOnly` — Download all files from the manifest and exit immediately; does not continue to installation.
* `-SingleDownloadMode` — Force single-threaded downloads.
* `-MaxConcurrentDownloads <n>` — Set the max number of concurrent downloads.
* `-DownloadCucoAndExit` / `-CucoOnly` — Download Cuco only, then exit.
* `-NoDiskSpaceCheck` — Disable the disk space check.
* `-ShowConfig` — Print the effective configuration to the console and exit.
* `-DryRun` — Run in dry-run mode (no downloads or installs; useful for validation).
* `-Help` / `-?` — Print a short usage message describing available CLI flags and exit.

If you want additional fields documented or examples added here, let me know and I will extend this file.