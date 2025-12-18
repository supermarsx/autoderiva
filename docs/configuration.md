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
    "ScanOnlyMissingDrivers": true,
    "WifiCleanupMode": "SingleOnly",
    "WifiProfileNameToDelete": "Null"
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
| `CucoBinaryPath` | string | `cuco/CtoolGui.exe` | Relative path (from `BaseUrl`) to the Cuco utility binary. |
| `DownloadCuco` | boolean | `true` | If `true`, Cuco is downloaded to the target directory. |
| `CucoTargetDir` | string | `Desktop` | Where to place Cuco (supports `Desktop`). |
| `AskBeforeDownloadCuco` | boolean | `false` | If `true`, asks for confirmation before downloading Cuco. |
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
| `ClearWifiProfiles` | boolean | `true` | Master switch for Wi‑Fi profile cleanup at end of run. |
| `AskBeforeClearingWifiProfiles` | boolean | `false` | If `true`, asks before deleting saved Wi‑Fi profiles. |
| `WifiCleanupMode` | string | `SingleOnly` | Wi‑Fi cleanup mode: `SingleOnly`, `All`, or `None`. |
| `WifiProfileNameToDelete` | string | `Null` | Profile name to delete when `WifiCleanupMode` is `SingleOnly`. |
| `AutoExitWithoutConfirmation` | boolean | `false` | If `true`, exits without waiting for confirmation at the end. |
| `ShowOnlyNonZeroStats` | boolean | `true` | If `true`, stats output hides 0 counters. |

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
- `-Help` / `-?`