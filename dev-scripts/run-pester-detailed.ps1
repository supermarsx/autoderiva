$env:AUTODERIVA_TEST='1'
Import-Module Pester -ErrorAction Stop
$config = [PesterConfiguration]::Default
$config.Run.Path = Join-Path (Resolve-Path $PSScriptRoot -ErrorAction SilentlyContinue).Path '..\tests'
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config -PassThru
$result | Format-List *
$failed = $result.FailedCount
Write-Host "Failed tests: $failed"
if ($failed -gt 0) {
    $result.FailedTests | ForEach-Object { Write-Host "FAILED: $($_.FullName)" }
}
