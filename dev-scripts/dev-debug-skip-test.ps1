$env:AUTODERIVA_TEST = '1'
$scriptFile = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'scripts\Install-AutoDeriva.ps1'
. $scriptFile
$driver = [PSCustomObject]@{ HardwareIDs = 'PCI\VEN_1234&DEV_ABCD'; SomeOther = 'value' }
$drivers = @($driver)
$Script:Test_GetRemoteCsv = { param($Url) $null = $Url; @() }
$Script:Test_InvokeConcurrentDownload = { param($FileList, $MaxConcurrency, $TestMode) $null = $FileList; $null = $MaxConcurrency; $null = $TestMode; return $true }
$temp = Join-Path $env:TEMP ('autoderiva_test_' + (Get-Random))
New-Item -ItemType Directory -Path $temp | Out-Null
$initial = $Script:Stats.DriversSkipped
$res = Install-Driver -DriverMatches $drivers -TempDir $temp
Write-Host "initial type: $($initial.GetType().FullName) value: $initial"
Write-Host "after type: $($Script:Stats.DriversSkipped.GetType().FullName) value: $($Script:Stats.DriversSkipped)"
Write-Host "res count: $($res | Measure-Object | Select-Object -ExpandProperty Count)"
$res | Format-List *
Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
