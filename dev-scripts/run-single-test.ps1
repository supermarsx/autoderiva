Import-Module Pester -ErrorAction Stop
$env:AUTODERIVA_TEST='1'
Invoke-Pester -Script .\tests\Install-AutoDeriva.CLI.Tests.ps1 -TestName 'Counts failed file downloads in TestMode' -Verbose -PassThru
