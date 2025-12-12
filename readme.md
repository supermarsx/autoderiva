# AutoDeriva

[![CI](https://github.com/supermarsx/autoderiva/actions/workflows/ci.yml/badge.svg)](https://github.com/supermarsx/autoderiva/actions/workflows/ci.yml)
![GitHub stars](https://img.shields.io/github/stars/supermarsx/autoderiva?style=social)
![GitHub forks](https://img.shields.io/github/forks/supermarsx/autoderiva?style=social)
![GitHub watchers](https://img.shields.io/github/watchers/supermarsx/autoderiva?style=social)
![Repo Size](https://img.shields.io/github/repo-size/supermarsx/autoderiva)
![Driver Count](https://img.shields.io/badge/Drivers-163+-blue)


**AutoDeriva** is a powerful, automated system setup and driver installer designed for remote and hybrid environments. It intelligently scans your system's hardware, matches it against a remote inventory of drivers, and automatically downloads and installs the necessary components.

## 🚀 Quick Start

Run the installer directly from PowerShell with this one-liner:

```powershell
irm https://raw.githubusercontent.com/supermarsx/autoderiva/main/scripts/Install-AutoDeriva.ps1 | iex
```

## ✨ Features

*   **Smart Driver Matching**: Uses Hardware IDs to identify and install only the drivers your system needs.
*   **Remote Inventory**: Fetches driver metadata and files from a remote repository, eliminating the need for a massive local driver store.
*   **Auto-Elevation**: Automatically requests administrative privileges to ensure seamless installation.
*   **Resilient Downloads**: Includes retry logic and exponential backoff for reliable file fetching.
*   **Disk Space Checks**: Verifies sufficient disk space before starting downloads.
*   **Detailed Logging**: Keeps a comprehensive log of all actions for troubleshooting.
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

## 🔧 Cuco Utility

AutoDeriva can automatically download the **Cuco Utility** (\CtoolGui.exe\) to your Desktop. This behavior is configurable:

*   **Enable/Disable**: Set \"DownloadCuco": false\ in your config to disable.
*   **Target Directory**: Configure \"CucoTargetDir"\ to specify a custom download location (defaults to "Desktop").

## 📜 Scripts

*   \Install-AutoDeriva.ps1\: The main installer script.
*   \startup-script.ps1\: A lightweight bootstrapper to launch the installer.
*   \Get-DriverInventory.ps1\: (Dev) Generates the driver inventory CSV.
*   \Get-DriverFileManifest.ps1\: (Dev) Generates the file manifest for the repository.
*   \dev-scripts/\: Contains build, lint, and test scripts for development.

---

*Maintained by [supermarsx](https://github.com/supermarsx)*
