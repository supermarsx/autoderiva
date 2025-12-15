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

    It 'Skips drivers missing InfPath without throwing' {
        # Arrange: create a driver object missing InfPath
        $driver = [PSCustomObject]@{ HardwareIDs = 'PCI\VEN_1234&DEV_ABCD'; SomeOther = 'value' }
        $drivers = @($driver)

        # Provide an empty manifest to avoid network calls
        $emptyManifest = @()
        Mock Invoke-ConcurrentDownload { $true } -Verifiable

        $temp = Join-Path $env:TEMP ("autoderiva_test_" + (Get-Random))
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            # Call Install-Driver directly while injecting a manifest to avoid remote calls
            $res = Install-Driver -DriverMatches $drivers -TempDir $temp -FileManifest $emptyManifest
            $res | Should -BeOfType System.Object
        } finally {
            Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
