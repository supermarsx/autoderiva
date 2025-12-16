Import-Module Pester -ErrorAction SilentlyContinue
$env:AUTODERIVA_TEST='1'
. $PSScriptRoot\..\scripts\Install-AutoDeriva.ps1

# Arrange
$file1 = @{ Url = 'https://example.com/file-ok.bin'; OutputPath = Join-Path $env:TEMP 'ok.bin' }
$file2 = @{ Url = 'https://example.com/file-fail.bin'; OutputPath = Join-Path $env:TEMP 'fail.bin' }
$list = @($file1, $file2)

# Test hook to simulate failing download
$Script:Test_InvokeDownloadFile = { param($Url, $OutputPath) $null = $OutputPath; if ($Url -like '*fail*') { return $false } else { return $true } }

$initialFailed = $Script:Stats.FilesDownloadFailed
$initialSuccess = $Script:Stats.FilesDownloaded

Write-Host "Initial FilesDownloadFailed: $initialFailed" -ForegroundColor Cyan
Write-Host "Initial FilesDownloaded: $initialSuccess" -ForegroundColor Cyan

Invoke-ConcurrentDownload -FileList $list -TestMode

Write-Host "Post FilesDownloadFailed: $($Script:Stats.FilesDownloadFailed)" -ForegroundColor Green
Write-Host "Post FilesDownloaded: $($Script:Stats.FilesDownloaded)" -ForegroundColor Green

if ($Script:Stats.FilesDownloadFailed -ge ($initialFailed + 1) -and $Script:Stats.FilesDownloaded -ge ($initialSuccess + 1)) {
    Write-Host "Testcase simulated: counters incremented" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Testcase failed: counters did not increment as expected" -ForegroundColor Red
    exit 2
}
