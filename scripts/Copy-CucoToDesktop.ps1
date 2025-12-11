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
} else {
    Write-Error "Failed to copy file."
}
