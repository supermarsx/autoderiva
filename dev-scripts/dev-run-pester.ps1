Import-Module Pester
$env:AUTODERIVA_TEST='1'
$result = Invoke-Pester -Script .\tests\Install-AutoDeriva.CLI.Tests.ps1 -PassThru -Verbose
$result | ConvertTo-Json -Depth 5 | Out-File -FilePath .\pester-result.json -Encoding utf8
