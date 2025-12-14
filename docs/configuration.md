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
| `EnableLogging` | boolean | `true` | Enable writing a runtime log file. The log file is generated in the repository root if enabled. |
| `LogLevel` | string | `INFO` | The logging verbosity. Supported values: `DEBUG`, `INFO`, `WARN`, `ERROR`. |
| `DownloadAllFiles` | boolean | `false` | If `true`, downloads *all* files from the manifest (useful for offline scenarios). |
| `CucoBinaryPath` | string | `cuco/CtoolGui.exe` | Relative path (from `BaseUrl`) to the Cuco utility binary. |
| `DownloadCuco` | boolean | `true` | If `true`, the Cuco utility is downloaded to the target directory. |
| `CucoTargetDir` | string | `Desktop` | Where to place the Cuco binary. `Desktop` resolves to the original user's Desktop folder when possible. |
| `MaxRetries` | integer | `5` | Number of retries the downloader will attempt on transient failures. |
| `MaxBackoffSeconds` | integer | `60` | Maximum backoff time (in seconds) between retry attempts. |
| `MinDiskSpaceMB` | integer | `3072` | Minimum free disk space required (in MB) for temporary downloads. Checked before the main download phase (unless disabled). |
| `CheckDiskSpace` | boolean | `true` | Enable/disable the disk space check (if `false`, the check is skipped). Default is `true`. |
| `MaxConcurrentDownloads` | integer | `6` | Maximum number of parallel download threads used by the Runspace-based downloader. Lower this on low-resource systems. |
| `SingleDownloadMode` | boolean | `false` | When `true`, forces `MaxConcurrentDownloads` to `1` and effectively disables concurrency. Default is `false`. |

Notes & behavior

- `SingleDownloadMode` is a convenience toggle that forces the downloader to operate one file at a time. This is useful on systems where concurrent downloads cause problems (e.g., due to throttling or instability).
- `CheckDiskSpace` is run before creating the temporary workspace; set it to `false` if you have special storage arrangements or don't want the script to perform the free-space check.
- To override defaults, create a `config.json` containing only the keys you want to change. Example above shows a minimal override.

Troubleshooting tips

- If downloads fail due to connection issues or throttling, try reducing `MaxConcurrentDownloads` or enable `SingleDownloadMode`.
- When enabling logging, inspect the generated log file (`autoderiva-<timestamp>.log`) in the repository root for detailed error messages.

CLI Overrides

Many of the configuration options can also be supplied as CLI flags when invoking `Install-AutoDeriva.ps1`. These flags will override values from `config.defaults.json` and `config.json`:

* `-ConfigPath <path>` — Load the specified JSON file as additional overrides.
* `-EnableLogging` — Enable logging regardless of config file.
* `-DownloadAllFiles` — Force download-all behavior.
* `-SingleDownloadMode` — Force single-threaded downloads.
* `-MaxConcurrentDownloads <n>` — Set the max number of concurrent downloads.
* `-NoDiskSpaceCheck` — Disable the disk space check.
* `-ShowConfig` — Print the effective configuration to the console and exit.
* `-DryRun` — Run in dry-run mode (no downloads or installs; useful for validation).

If you want additional fields documented or examples added here, let me know and I will extend this file.