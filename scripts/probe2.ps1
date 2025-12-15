$env:AUTODERIVA_TEST = '1'
. "$PSScriptRoot\Install-AutoDeriva.ps1"
if (Get-Command Get-RemoteCsv -ErrorAction SilentlyContinue) {
    Write-Host 'Get-RemoteCsv exists'
}
else {
    Write-Host 'Get-RemoteCsv MISSING'
}
