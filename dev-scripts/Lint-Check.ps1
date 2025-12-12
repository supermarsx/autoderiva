<#
.SYNOPSIS
    Runs PSScriptAnalyzer on all scripts in the repository.

.DESCRIPTION
    This script executes PSScriptAnalyzer against the 'scripts' and 'dev-scripts' directories.
    It checks for any violations with a severity of Error or Warning.
    This ensures code quality and adherence to best practices.

.EXAMPLE
    .\dev-scripts\Lint-Check.ps1
#>

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path

Write-Host "Running PSScriptAnalyzer..." -ForegroundColor Cyan

$paths = @(
    Join-Path $repoRoot "scripts"
    Join-Path $repoRoot "dev-scripts"
)

$results = @()
foreach ($path in $paths) {
    $results += Invoke-ScriptAnalyzer -Path $path -Recurse -Severity Error, Warning -ExcludeRule PSAvoidUsingWriteHost
}

if ($results) {
    $results | Format-Table -AutoSize
    Write-Error "Lint check failed. Found $( $results.Count ) issues."
}
else {
    Write-Host "Lint check passed! No issues found." -ForegroundColor Green
}
