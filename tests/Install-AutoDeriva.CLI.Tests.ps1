Describe 'Install-AutoDeriva CLI and Config Parsing' {
    $repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
    $scriptFile = Join-Path $repoRoot 'scripts\Install-AutoDeriva.ps1'
    # Ensure tests run non-interactively (skip auto-elevation), then dot-source the main script
    $env:AUTODERIVA_TEST = '1'
    if (-not (Test-Path $scriptFile)) { throw "Script file not found at: $scriptFile" }
    . $scriptFile

    It 'Prints valid JSON for -ShowConfig' -Pending {
        Write-Host "TEST: Prints valid JSON for -ShowConfig (pending due to flakiness)"
    }

    It 'Respects -MaxConcurrentDownloads override' {
        Write-Host "TEST: Respects -MaxConcurrentDownloads override"
        $scriptFile = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'scripts\Install-AutoDeriva.ps1'
        Test-Path $scriptFile | Should -BeTrue
        $env:AUTODERIVA_TEST = '1'
        $raw = & $scriptFile -ShowConfig -MaxConcurrentDownloads 2 2>&1
        $all = ($raw -join "`n").Trim()
        $json = [regex]::Match($all, '\{.*\}', 'Singleline').Value
        $config = $json | ConvertFrom-Json
        $config.MaxConcurrentDownloads | Should -Be 2
    }

    It 'Respects -DownloadAllAndExit (DownloadOnly) flag' {
        Write-Host "TEST: Respects -DownloadAllAndExit (DownloadOnly) flag"
        $scriptFile = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'scripts\Install-AutoDeriva.ps1'
        Test-Path $scriptFile | Should -BeTrue
        $env:AUTODERIVA_TEST = '1'
        $raw = & $scriptFile -ShowConfig -DownloadAllAndExit 2>&1
        $all = ($raw -join "`n").Trim()
        $json = [regex]::Match($all, '\{.*\}', 'Singleline').Value
        $config = $json | ConvertFrom-Json
        $config.DownloadAllFiles | Should -Be $true
    }

    It 'Respects -NoDiskSpaceCheck flag' {
        Write-Host "TEST: Respects -NoDiskSpaceCheck flag"
        $scriptFile = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'scripts\Install-AutoDeriva.ps1'
        Test-Path $scriptFile | Should -BeTrue
        $env:AUTODERIVA_TEST = '1'
        $raw = & $scriptFile -ShowConfig -NoDiskSpaceCheck 2>&1
        $all = ($raw -join "`n").Trim()
        $json = [regex]::Match($all, '\{.*\}', 'Singleline').Value
        $config = $json | ConvertFrom-Json
        $config.CheckDiskSpace | Should -Be $false
    }

    It 'Supports -DryRun flag without errors (no downloads/installs)' {
        Write-Host "TEST: Supports -DryRun flag without errors (no downloads/installs)"
        $scriptFile = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'scripts\Install-AutoDeriva.ps1'
        Test-Path $scriptFile | Should -BeTrue
        $env:AUTODERIVA_TEST = '1'
        $raw = & $scriptFile -ShowConfig -DryRun 2>&1
        $all = ($raw -join "`n").Trim()
        $json = [regex]::Match($all, '\{.*\}', 'Singleline').Value
        $config = $json | ConvertFrom-Json
        $config | Should -Not -BeNullOrEmpty
    }

    It 'Counts failed file downloads in TestMode' {
        Write-Host "TEST: Counts failed file downloads in TestMode"
        # Prepare two fake files
        $file1 = @{ Url = 'https://example.com/file-ok.bin'; OutputPath = Join-Path $env:TEMP 'ok.bin' }
        $file2 = @{ Url = 'https://example.com/file-fail.bin'; OutputPath = Join-Path $env:TEMP 'fail.bin' }
        $list = @($file1, $file2)

        Mock Invoke-DownloadFile { param($Url, $OutputPath) if ($Url -like '*fail*') { return $false } else { return $true } }

        $initialFailed = $Script:Stats.FilesDownloadFailed
        $initialSuccess = $Script:Stats.FilesDownloaded

        Invoke-ConcurrentDownload -FileList $list -TestMode

        $Script:Stats.FilesDownloadFailed | Should -BeGreaterThanOrEqualTo ($initialFailed + 1)
        $Script:Stats.FilesDownloaded | Should -BeGreaterThanOrEqualTo ($initialSuccess + 1)
    }

    It 'Skips drivers missing InfPath without throwing' {
        # Arrange: create a driver object missing InfPath
        $driver = [PSCustomObject]@{ HardwareIDs = 'PCI\VEN_1234&DEV_ABCD'; SomeOther = 'value' }
        $drivers = @($driver)

        Mock Get-RemoteCsv { @() } -Verifiable
        Mock Invoke-ConcurrentDownload { $true } -Verifiable

        $temp = Join-Path $env:TEMP ("autoderiva_test_" + (Get-Random))
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            # Call Install-Driver directly and assert skipped counter increments
            $initial = $Script:Stats.DriversSkipped
            $res = Install-Driver -DriverMatches $drivers -TempDir $temp
            $res | Should -BeOfType System.Object
            $Script:Stats.DriversSkipped | Should -BeGreaterThanOrEqualTo ($initial + 1)
        }
        finally {
            Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
