$ErrorActionPreference = 'Stop'
$env:AUTODERIVA_TEST='1'
. .\scripts\Install-AutoDeriva.ps1
$file1 = @{ Url = 'https://example.com/file-ok.bin'; OutputPath = Join-Path $env:TEMP 'ok.bin' }
$file2 = @{ Url = 'https://example.com/file-fail.bin'; OutputPath = Join-Path $env:TEMP 'fail.bin' }
$list=@($file1,$file2)
$Script:Test_InvokeDownloadFile = { param($Url,$OutputPath) $null = $OutputPath; if ($Url -like '*fail*') { return $false } else { return $true } }

try {
    Invoke-ConcurrentDownload -FileList $list -TestMode
    Write-Host 'Success'
}
catch {
    Write-Host 'Caught Exception:'
    Write-Host $_.Exception.Message
    Write-Host $_.ScriptStackTrace
    Write-Host $_.Exception.StackTrace
}
