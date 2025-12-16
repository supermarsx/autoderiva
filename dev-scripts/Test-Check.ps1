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

# Default to Normal verbosity to reduce output volume (helps VS Code not hang).
# Override by setting AUTODERIVA_PESTER_VERBOSE=Detailed|Diagnostic|Normal
$verbosity = $env:AUTODERIVA_PESTER_VERBOSE
if ([string]::IsNullOrWhiteSpace($verbosity)) {
    $verbosity = "Normal"
}
$config.Output.Verbosity = $verbosity

Invoke-Pester -Configuration $config
