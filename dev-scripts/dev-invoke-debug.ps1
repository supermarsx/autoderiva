$env:AUTODERIVA_TEST = '1'
. .\scripts\Install-AutoDeriva.ps1
$file1 = @{ Url = 'https://example.com/file-ok.bin'; OutputPath = Join-Path $env:TEMP 'ok.bin' }
$file2 = @{ Url = 'https://example.com/file-fail.bin'; OutputPath = Join-Path $env:TEMP 'fail.bin' }
$list = @($file1, $file2)
$Script:Test_InvokeDownloadFile = { param($Url, $OutputPath) if ($Url -like '*fail*') { return $false } else { return $true } }
Write-Host "About to call Invoke-ConcurrentDownload (TestMode)"
try {
    Invoke-ConcurrentDownload -FileList $list -TestMode -Verbose
    Write-Host "Invoke-ConcurrentDownload completed successfully"
}
catch {
    Write-Host "ERROR: $_"
}

try {
    Invoke-ConcurrentDownload -FileList $list -MaxConcurrency 6 -TestMode -Verbose
    Write-Host "Invoke-ConcurrentDownload completed successfully (with MaxConcurrency)"
}
catch {
    Write-Host "ERROR with MaxConcurrency: $_"
}
Write-Host "Done."