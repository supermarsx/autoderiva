Describe 'Unknown devices CSV export' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'
        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile
    }

    It 'Exports unknown devices to CSV using test hook' {
        $tmpDir = Join-Path $env:TEMP ("autoderiva_unknown_export_" + (Get-Random))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $outPath = Join-Path $tmpDir 'unknown_devices.csv'

        $Script:Test_GetUnknownDevicesForExport = {
            @(
                [PSCustomObject]@{ InstanceId = 'PCI\\VEN_1111&DEV_2222'; FriendlyName = 'Dev1'; ProblemCode = 28; HardwareIds = 'PCI\\VEN_1111&DEV_2222' },
                [PSCustomObject]@{ InstanceId = 'PCI\\VEN_AAAA&DEV_BBBB'; FriendlyName = 'Dev2'; ProblemCode = 28; HardwareIds = 'PCI\\VEN_AAAA&DEV_BBBB' }
            )
        }

        try {
            Export-AutoDerivaUnknownDevicesCsv -Path $outPath
            Test-Path -LiteralPath $outPath | Should -BeTrue
            $rows = Import-Csv -LiteralPath $outPath
            $rows.Count | Should -Be 2
            ($rows[0].PSObject.Properties.Name -contains 'InstanceId') | Should -BeTrue
            ($rows[0].PSObject.Properties.Name -contains 'ProblemCode') | Should -BeTrue
        }
        finally {
            $Script:Test_GetUnknownDevicesForExport = $null
            Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
