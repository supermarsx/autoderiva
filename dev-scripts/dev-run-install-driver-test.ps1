$env:AUTODERIVA_TEST='1'
$scriptFile = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'scripts\Install-AutoDeriva.ps1'
. $scriptFile
$driver = [PSCustomObject]@{ HardwareIDs = 'PCI\VEN_1234&DEV_ABCD'; SomeOther = 'value' }
$drivers = @($driver)
$Script:Test_GetRemoteCsv = { param($Url) $null = $Url; @() }
$Script:Test_InvokeConcurrentDownload = { param($FileList,$MaxConcurrency,$TestMode) $null = $FileList; $null = $MaxConcurrency; $null = $TestMode; return $true }
$temp = Join-Path $env:TEMP ('autoderiva_test_' + (Get-Random))
New-Item -ItemType Directory -Path $temp | Out-Null
$res = Install-Driver -DriverMatches $drivers -TempDir $temp
Write-Host "RES TYPE:" ($null -ne $res ? $res.GetType().FullName : '<null>')
Write-Host "RES COUNT:" ($res | Measure-Object | Select-Object -ExpandProperty Count)
Write-Host "STATS DriversSkipped:" $Script:Stats.DriversSkipped
Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
