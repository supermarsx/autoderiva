# Scripts

This folder contains utility scripts for working with the repository.

- `Get-DriverFolders.ps1` — generates `driver_folders.txt` (list of driver folders containing .inf files).
- `Get-NonDriverFolders.ps1` — generates `non_driver_folders.txt` (folders with files but no .inf files).
- `Inventory-Drivers.ps1` — creates `driver_inventory.csv` with per- .inf file metadata.
- `Get-SystemHardwareIDs.ps1` — exports current system hardware IDs to `system_hardware_ids.csv`.
- `Count-Languages.ps1` — counts languages in the repo but *ignores* `drivers` and `cuco` by default. It will use `cloc` if available (recommended) or fallback to a simple internal scanner.
- `cloc_excludes.txt` — default exclude list for `cloc` and `Count-Languages.ps1`.

Usage:
```powershell
# Count languages (defaults to excluding drivers and cuco)
.\/scripts\/Count-Languages.ps1

# Use a custom additional exclude
.\/scripts\/Count-Languages.ps1 -ExtraExcludes @('third_party','tools')

# Or point to a custom exclude file
.\/scripts\/Count-Languages.ps1 -ExcludeListFile .\my_excludes.txt
```

Tips:
- GitHub language statistics will also ignore `drivers` and `cuco` because `.gitattributes` marks them as `linguist-vendored`.
- If you use `cloc`, keep `cloc` installed to get the most accurate results.
