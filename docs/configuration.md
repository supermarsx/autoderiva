# AutoDeriva Configuration Reference

This document describes the configuration file format and the supported keys for AutoDeriva.

## Configuration sources & precedence

The installer merges configuration using the following precedence (later wins):

1. Internal defaults (built into the script)
2. `config.defaults.json` (repo root, if present)
3. `config.json` (repo root, if present)
4. Remote JSON overrides (optional)
     - from `RemoteConfigUrl` (config key), or
     - from `-ConfigUrl` (CLI), which overrides `RemoteConfigUrl`
5. `-ConfigPath` (CLI JSON file overrides)
6. CLI switches/arguments (e.g. `-SingleDownloadMode`, `-MaxConcurrentDownloads 1`, …)

Notes:

- When `config.defaults.json` is missing locally, the installer attempts to fetch it from the repo’s raw URL.
- When `AUTODERIVA_TEST=1`, the script skips fetching remote overrides via `RemoteConfigUrl` unless you explicitly pass `-ConfigUrl`.

## Example `config.json`

This file lives at the repo root and should contain only the keys you want to override:

```json
{
    "MaxConcurrentDownloads": 4,
    "SingleDownloadMode": false,
    "ScanOnlyMissingDrivers": true
}
```

## Configuration keys

Defaults shown below match `config.defaults.json`.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `BaseUrl` | string | `https://raw.githubusercontent.com/supermarsx/autoderiva/main/` | Base URL used to fetch manifests and driver files. Should end with `/`. |
| `InventoryPath` | string | `exports/driver_inventory.csv` | Path (relative to `BaseUrl`) to the driver inventory CSV. |
| `ManifestPath` | string | `exports/driver_file_manifest.csv` | Path (relative to `BaseUrl`) to the driver file manifest CSV. |
| `RemoteConfigUrl` | string/null | `null` | Optional URL to a JSON document applied as overrides (after local configs). |
| `EnableLogging` | boolean | `true` | Enable writing a runtime log file under `logs/`. |
| `LogLevel` | string | `INFO` | Logging verbosity (`DEBUG`, `INFO`, `WARN`, `ERROR`). |
| `AutoCleanupLogs` | boolean | `true` | If `true`, deletes old log files using the retention rules below. |
| `LogRetentionDays` | integer | `10` | Delete log files older than this many days. Set to `0` to disable age-based cleanup. |
| `MaxLogFiles` | integer | `15` | Keep at most this many log files (newest kept). Set to `0` to disable count-based cleanup. |
| `DownloadAllFiles` | boolean | `false` | If `true`, downloads *all* files from the manifest (offline caching scenario). |
| `CucoPrimaryUrl` | string | `https://cuco.inforlandia.pt/uagent/CtoolGui.exe` | Primary URL to download the Cuco binary from. |
| `CucoSecondaryUrl` | string/null | `null` | Secondary URL for Cuco. When `null`, AutoDeriva uses `BaseUrl + CucoBinaryPath` as the secondary source. |
| `CucoDownloadUrl` | string | `https://cuco.inforlandia.pt/uagent/CtoolGui.exe` | Legacy alias for `CucoPrimaryUrl` (kept for backward compatibility). |
| `CucoBinaryPath` | string | `cuco/CtoolGui.exe` | Relative path (from `BaseUrl`) used to derive the default secondary URL when `CucoSecondaryUrl` is `null`. |
| `DownloadCuco` | boolean | `true` | If `true`, Cuco is downloaded to the target directory. |
| `CucoTargetDir` | string | `Desktop` | Where to place Cuco (supports `Desktop`). |
| `AskBeforeDownloadCuco` | boolean | `false` | If `true`, asks for confirmation before downloading Cuco. |
| `CucoExistingFilePolicy` | string | `Skip` | What to do if `CtoolGui.exe` already exists in `CucoTargetDir`: `Skip` (default) or `Overwrite`. |
| `MaxRetries` | integer | `5` | Number of retries for transient download failures. |
| `MaxBackoffSeconds` | integer | `60` | Maximum retry backoff (seconds). |
| `MinDiskSpaceMB` | integer | `3072` | Minimum free disk space required (MB) for temporary downloads. |
| `CheckDiskSpace` | boolean | `true` | Enable/disable disk space checks. |
| `MaxConcurrentDownloads` | integer | `6` | Maximum number of parallel downloads (runspace-based downloader). |
| `SingleDownloadMode` | boolean | `false` | When `true`, forces `MaxConcurrentDownloads` to `1`. |
| `VerifyFileHashes` | boolean | `false` | If `true`, verifies downloaded files using the `Sha256` column from the file manifest CSV. Disabled by default. |
| `DeleteFilesOnHashMismatch` | boolean | `false` | If `true`, deletes a downloaded file when its SHA256 mismatches. Default is to warn and keep the file. |
| `HashMismatchPolicy` | string | `Continue` | What to do when a file hash mismatches (when `VerifyFileHashes` is enabled): `Continue` (default; install anyway), `SkipDriver` (skip installing affected drivers), or `Abort` (stop driver installation phase). |
| `HashVerifyMode` | string | `Parallel` | Hash verification mode when `VerifyFileHashes` is enabled: `Parallel` or `Single`. |
| `HashVerifyMaxConcurrency` | integer | `5` | Max number of files to hash in parallel when `HashVerifyMode` is `Parallel`. |
| `ScanOnlyMissingDrivers` | boolean | `true` | When `true`, scans only devices missing drivers (PnP ProblemCode `28`). |
| `DeviceScanMode` | string | `Parallel` | Device scan mode for ProblemCode queries: `Parallel` (runspaces) or `Single` (serial). |
| `DeviceScanMaxConcurrency` | integer | `8` | Max parallel workers for device scan (ProblemCode queries). Set to `1` to force single-threaded scan. |
| `AutoExitWithoutConfirmation` | boolean | `false` | If `true`, exits without waiting for confirmation at the end. |
| `ShowOnlyNonZeroStats` | boolean | `true` | If `true`, stats output hides 0 counters. |
| `DisableOneDriveStartup` | boolean | `true` | If `true`, removes OneDrive from startup (does not uninstall/disable OneDrive). |
| `HideTaskViewButton` | boolean | `true` | If `true`, hides the Task View button on the taskbar. |
| `DisableNewsAndInterestsAndWidgets` | boolean | `true` | If `true`, disables News/Interests (Win10 feeds policy + taskbar setting) and hides Widgets (Win11). |
| `HideTaskbarSearch` | boolean | `true` | If `true`, hides the Search icon/box on the taskbar. |

## Preflight checks

These keys control the "Preflight Checks" section shown at startup.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `PreflightEnabled` | boolean | `true` | Master switch for all preflight checks. |
| `PreflightCheckAdmin` | boolean | `true` | If `true`, prints whether the script is running elevated. |
| `PreflightCheckLogWritable` | boolean | `true` | If `true`, attempts a best-effort write to the current log file (when logging is enabled). |
| `PreflightCheckNetwork` | boolean | `true` | If `true`, runs network/DNS/HTTP checks (skipped automatically in `AUTODERIVA_TEST=1`). |
| `PreflightInternetFailurePolicy` | string | `Exit` | What to do if the Internet (DNS) check fails: `Exit` (default) or `Warn`. |
| `PreflightHttpTimeoutMs` | integer | `4000` | Timeout in milliseconds for each HTTP preflight check. |
| `PreflightCheckGitHub` | boolean | `true` | If `true`, checks connectivity to `https://github.com/`. |
| `PreflightCheckBaseUrl` | boolean | `true` | If `true`, checks connectivity to the configured `BaseUrl` (HEAD with GET fallback). |
| `PreflightCheckGoogle` | boolean | `true` | If `true`, checks connectivity to `https://www.google.com/generate_204`. |
| `PreflightCheckCucoSite` | boolean | `true` | If `true`, checks reachability of the Cuco site URL below. |
| `PreflightCucoUrl` | string | `https://cuco.inforlandia.pt/` | URL to check for Cuco reachability. |
| `PreflightPingEnabled` | boolean | `true` | If `true`, runs an ICMP ping check (warn-only; ICMP can be blocked). |
| `PreflightPingTarget` | string | `1.1.1.1` | Target hostname/IP for the ping check. |
| `PreflightPingTimeoutMs` | integer | `2000` | Ping timeout (milliseconds). |
| `PreflightPingLatencyWarnMs` | integer | `150` | Ping latency threshold (ms) that triggers a warning about potential slow connection. |

## Wi-Fi profile cleanup

These keys control optional Wi-Fi profile cleanup at the end of the run (or via `-ClearWifiAndExit`).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ClearWifiProfiles` | boolean | `true` | Master switch for Wi-Fi profile cleanup at end of run. |
| `AskBeforeClearingWifiProfiles` | boolean | `false` | If `true`, asks before deleting saved Wi-Fi profiles. |
| `WifiCleanupMode` | string | `SingleOnly` | Wi-Fi cleanup mode: `SingleOnly`, `All`, or `None`. |
| `WifiProfileNameToDelete` | string | `Null` | Profile name to delete when `WifiCleanupMode` is `SingleOnly`. |

## CLI options (high level)

CLI flags override config files and are the most convenient way to change behavior for a single run.

Config overrides:

- `-ConfigPath <path>`: Load a local JSON file as overrides.
- `-ConfigUrl <url>`: Load JSON overrides from a URL (overrides `RemoteConfigUrl`).
- `-ShowConfig`: Print the effective merged configuration and exit.

Logging:

- `-EnableLogging`
- `-CleanLogs`
- `-LogRetentionDays <n>`
- `-MaxLogFiles <n>`
- `-NoLogCleanup`

Download behavior:

- `-DownloadAllFiles`
- `-DownloadAllAndExit` (alias: `-DownloadOnly`)
- `-SingleDownloadMode`
- `-MaxConcurrentDownloads <n>`
- `-NoDiskSpaceCheck`
- `-VerifyFileHashes <true|false>`
- `-DeleteFilesOnHashMismatch <true|false>`
- `-HashMismatchPolicy <Continue|SkipDriver|Abort>`
- `-HashVerifyMode <Parallel|Single>`
- `-HashVerifyMaxConcurrency <n>`

Cuco:

- `-DownloadCuco`
- `-DownloadCucoAndExit` (alias: `-CucoOnly`)
- `-CucoTargetDir <path>`
- `-AskBeforeDownloadCuco` / `-NoAskBeforeDownloadCuco`

Driver scan behavior:

- `-ScanOnlyMissingDrivers`
- `-ScanAllDevices`
- `-DeviceScanMode <Parallel|Single>`
- `-DeviceScanMaxConcurrency <n>`

Device export:

- `-ExportUnknownDevicesCsv <path>`: Export devices missing drivers (PnP ProblemCode `28`) to a CSV file and exit.

Wi‑Fi cleanup behavior:

- `-ClearWifiAndExit` (aliases: `-WifiOnly`, `-WifiCleanupAndExit`)
- `-ClearWifiProfiles` / `-NoWifiCleanup` (alias: `-NoClearWifiProfiles`)
- `-WifiCleanupMode <SingleOnly|All|None>`
- `-WifiProfileNameToDelete <name>` (aliases: `-WifiName`, `-WifiProfileName`)
- `-AskBeforeClearingWifiProfiles` / `-NoAskBeforeClearingWifiProfiles`

End-of-run behavior:

- `-AutoExitWithoutConfirmation` / `-RequireExitConfirmation`

Stats:

- `-ShowOnlyNonZeroStats` / `-ShowAllStats`

Other:

- `-DryRun`
- `-ShowBanner <true|false>`
- `-Help` / `-?`