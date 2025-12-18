Describe 'Install-AutoDeriva CLI and Config Parsing' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'

        # Ensure tests run non-interactively (skip auto-elevation)
        $env:AUTODERIVA_TEST = '1'
        if (-not (Test-Path $script:ScriptFile)) { throw "Script file not found at: $script:ScriptFile" }

        # Dot-source so function-level tests can directly call helpers when needed
        . $script:ScriptFile

        function script:Get-AutoDerivaEffectiveConfig {
            param(
                [Parameter(Mandatory = $true)][string]$ScriptFile,
                [Parameter(Mandatory = $true)][hashtable]$Params
            )

            $env:AUTODERIVA_TEST = '1'
            $raw = & $ScriptFile @Params 2>&1
            $all = ($raw -join "`n").Trim()

            $m = [regex]::Match($all, 'AUTODERIVA::CONFIG::(\{.*\})', 'Singleline')
            if (-not $m.Success) {
                throw "Did not find AUTODERIVA::CONFIG output. Output was: $all"
            }
            return ($m.Groups[1].Value | ConvertFrom-Json)
        }
    }

    It 'Prints valid JSON for -ShowConfig' -Pending {
        Write-Host "TEST: Prints valid JSON for -ShowConfig (pending due to flakiness)"
    }

    It 'Respects -MaxConcurrentDownloads override' {
        Write-Host "TEST: Respects -MaxConcurrentDownloads override"
        Test-Path $script:ScriptFile | Should -BeTrue
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; MaxConcurrentDownloads = 2 }
        $config.MaxConcurrentDownloads | Should -Be 2
    }

    It 'Respects -DownloadAllAndExit (DownloadOnly) flag' {
        Write-Host "TEST: Respects -DownloadAllAndExit (DownloadOnly) flag"
        Test-Path $script:ScriptFile | Should -BeTrue
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; DownloadAllAndExit = $true }
        $config.DownloadAllFiles | Should -Be $true
    }

    It 'Respects -NoDiskSpaceCheck flag' {
        Write-Host "TEST: Respects -NoDiskSpaceCheck flag"
        Test-Path $script:ScriptFile | Should -BeTrue
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; NoDiskSpaceCheck = $true }
        $config.CheckDiskSpace | Should -Be $false
    }

    It 'Respects -VerifyFileHashes <bool> override' {
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; VerifyFileHashes = $true }
        $config.VerifyFileHashes | Should -BeTrue

        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; VerifyFileHashes = $false }
        $config.VerifyFileHashes | Should -BeFalse
    }

    It 'Respects -DeleteFilesOnHashMismatch <bool> override' {
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; DeleteFilesOnHashMismatch = $true }
        $config.DeleteFilesOnHashMismatch | Should -BeTrue

        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; DeleteFilesOnHashMismatch = $false }
        $config.DeleteFilesOnHashMismatch | Should -BeFalse
    }

    It 'Supports -DryRun flag without errors (no downloads/installs)' {
        Write-Host "TEST: Supports -DryRun flag without errors (no downloads/installs)"
        Test-Path $script:ScriptFile | Should -BeTrue
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; DryRun = $true }
        $config | Should -Not -BeNullOrEmpty
    }

    It 'Respects -AskBeforeDownloadCuco and -NoAskBeforeDownloadCuco flags' {
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; AskBeforeDownloadCuco = $true }
        $config.AskBeforeDownloadCuco | Should -BeTrue

        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; NoAskBeforeDownloadCuco = $true }
        $config.AskBeforeDownloadCuco | Should -BeFalse

        # If both are provided, the latter assignment in the script should win (NoAsk... sets false)
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; AskBeforeDownloadCuco = $true; NoAskBeforeDownloadCuco = $true }
        $config.AskBeforeDownloadCuco | Should -BeFalse
    }

    It 'Respects -ScanAllDevices and -ScanOnlyMissingDrivers flags' {
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; ScanOnlyMissingDrivers = $true }
        $config.ScanOnlyMissingDrivers | Should -BeTrue

        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; ScanAllDevices = $true }
        $config.ScanOnlyMissingDrivers | Should -BeFalse

        # If both are provided, ScanAllDevices should win (sets ScanOnlyMissingDrivers false)
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; ScanOnlyMissingDrivers = $true; ScanAllDevices = $true }
        $config.ScanOnlyMissingDrivers | Should -BeFalse
    }

    It 'Respects -ShowAllStats and -ShowOnlyNonZeroStats flags' {
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; ShowOnlyNonZeroStats = $true }
        $config.ShowOnlyNonZeroStats | Should -BeTrue

        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; ShowAllStats = $true }
        $config.ShowOnlyNonZeroStats | Should -BeFalse
    }

    It 'Respects Wi-Fi cleanup toggles and mode values' {
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; NoWifiCleanup = $true }
        $config.ClearWifiProfiles | Should -BeFalse
        $config.WifiCleanupMode | Should -Be 'None'

        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; WifiCleanupMode = 'All' }
        $config.WifiCleanupMode | Should -Be 'All'

        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; WifiProfileNameToDelete = 'MyHotspot' }
        $config.WifiProfileNameToDelete | Should -Be 'MyHotspot'
    }

    It 'Supports -ClearWifiAndExit without errors (test mode skips deletion)' {
        $env:AUTODERIVA_TEST = '1'
        { & $script:ScriptFile -ClearWifiAndExit | Out-Null } | Should -Not -Throw
    }

    It 'Accepts -WifiName alias for WifiProfileNameToDelete' {
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; WifiName = 'AliasHotspot' }
        $config.WifiProfileNameToDelete | Should -Be 'AliasHotspot'
    }

    It 'Respects end-of-run confirmation toggles' {
        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; AutoExitWithoutConfirmation = $true }
        $config.AutoExitWithoutConfirmation | Should -BeTrue

        $config = Get-AutoDerivaEffectiveConfig -ScriptFile $script:ScriptFile -Params @{ ShowConfig = $true; RequireExitConfirmation = $true }
        $config.AutoExitWithoutConfirmation | Should -BeFalse
    }

    It 'Counts failed file downloads in TestMode' {
        Write-Host "TEST: Counts failed file downloads in TestMode"
        $scriptFile = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'scripts\Install-AutoDeriva.ps1'
        $env:AUTODERIVA_TEST = '1'
        . $scriptFile
        # Prepare two fake files
        $file1 = @{ Url = 'https://example.com/file-ok.bin'; OutputPath = Join-Path $env:TEMP 'ok.bin' }
        $file2 = @{ Url = 'https://example.com/file-fail.bin'; OutputPath = Join-Path $env:TEMP 'fail.bin' }
        $list = @($file1, $file2)

        # Use the script-level test hook to simulate a failing download without Pester Mock
        $Script:Test_InvokeDownloadFile = { param($Url, $OutputPath) if ($Url -like '*fail*') { return $false } else { return $true } }

        $initialFailed = $Script:Stats.FilesDownloadFailed
        $initialSuccess = $Script:Stats.FilesDownloaded

        Invoke-ConcurrentDownload -FileList $list -TestMode

        $Script:Stats.FilesDownloadFailed | Should -BeGreaterOrEqual ($initialFailed + 1)
        $Script:Stats.FilesDownloaded | Should -BeGreaterOrEqual ($initialSuccess + 1)
    }

    It 'Skips drivers missing InfPath without throwing' {
        # Arrange: create a driver object missing InfPath
        $scriptFile = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'scripts\Install-AutoDeriva.ps1'
        $env:AUTODERIVA_TEST = '1'
        . $scriptFile
        $driver = [PSCustomObject]@{ HardwareIDs = 'PCI\VEN_1234&DEV_ABCD'; SomeOther = 'value' }
        $drivers = @($driver)

        # Use script-level test hooks to avoid depending on Pester's Mock behavior
        $Script:Test_GetRemoteCsv = { param($Url) @() }
        $Script:Test_InvokeConcurrentDownload = { param($FileList, $MaxConcurrency, $TestMode) return $true }

        $temp = Join-Path $env:TEMP ("autoderiva_test_" + (Get-Random))
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            # Call Install-Driver directly and assert skipped counter increments
            $initial = $Script:Stats.DriversSkipped
            $res = Install-Driver -DriverMatches $drivers -TempDir $temp
            # Ensure we receive a non-null/non-empty result (one or more skipped records)
            $res | Should -Not -BeNullOrEmpty
            ($Script:Stats.DriversSkipped -ge ($initial + 1)) | Should -BeTrue
        }
        finally {
            Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
