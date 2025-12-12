<#
.SYNOPSIS
    Runs a full build check (Lint + Tests).

.DESCRIPTION
    This script orchestrates the build verification process.
    1. Runs Lint-Check.ps1
    2. Runs Test-Check.ps1
    
    If any step fails, the build is considered failed.

.EXAMPLE
    .\dev-scripts\Build-Check.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host "Starting Build Check..." -ForegroundColor Cyan

try {
    # 1. Format Check
    Write-Host "`n[Step 1/3] Formatting..." -ForegroundColor Yellow
    & "$PSScriptRoot\Format-Check.ps1"

    # 2. Lint Check
    Write-Host "`n[Step 2/3] Linting..." -ForegroundColor Yellow
    & "$PSScriptRoot\Lint-Check.ps1"

    # 3. Test Check
    Write-Host "`n[Step 3/3] Testing..." -ForegroundColor Yellow
    & "$PSScriptRoot\Test-Check.ps1"

    Write-Host "`nBuild Check Passed Successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Build Check Failed: $_"
}
finally {
    Write-Host "`n"
}
