<#
.SYNOPSIS
    Runs Pester tests for the repository.

.DESCRIPTION
    This script executes all Pester tests located in the 'tests' directory.
    It validates script syntax and runs any defined unit/integration tests.

.EXAMPLE
    .\dev-scripts\Test-Check.ps1
#>

$ErrorActionPreference = "Stop"

# Ensure Pester is imported to access [PesterConfiguration]
Import-Module Pester -ErrorAction Stop

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$testsPath = Join-Path $repoRoot "tests"

Write-Host "Running Pester Tests..." -ForegroundColor Cyan

$config = [PesterConfiguration]::Default
$config.Run.Path = $testsPath
$config.Output.Verbosity = "Detailed"

Invoke-Pester -Configuration $config
