<#
.SYNOPSIS
    Copies the 'cuco' utility (CtoolGui.exe) to the current user's Desktop.

.DESCRIPTION
    This script locates the 'CtoolGui.exe' file in the 'cuco' directory of the repository
    and copies it to the Desktop of the currently logged-in user.
    It overwrites the destination file if it already exists.

.EXAMPLE
    .\scripts\Copy-CucoToDesktop.ps1
#>

$ErrorActionPreference = "Stop"

# Determine paths
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$sourceFile = Join-Path $repoRoot "cuco\CtoolGui.exe"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$destinationFile = Join-Path $desktopPath "CtoolGui.exe"

# Check if source exists
if (-not (Test-Path $sourceFile)) {
    Write-Error "Source file not found: $sourceFile"
}

Write-Host "Copying '$sourceFile' to '$destinationFile'..."

# Copy the file
Copy-Item -Path $sourceFile -Destination $destinationFile -Force

if (Test-Path $destinationFile) {
    Write-Host "Success! File copied to Desktop." -ForegroundColor Green
}
else {
    Write-Error "Failed to copy file."
}
