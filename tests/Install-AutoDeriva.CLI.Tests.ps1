Describe 'Install-AutoDeriva CLI and Config Parsing' {
    $repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
    $scriptFile = Join-Path $repoRoot 'scripts\Install-AutoDeriva.ps1'

    It 'Prints valid JSON for -ShowConfig' {
        $scriptFile = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'scripts\Install-AutoDeriva.ps1'
        Test-Path $scriptFile | Should -BeTrue
        $env:AUTODERIVA_TEST = '1'
        $raw = & $scriptFile -ShowConfig 2>&1
        $all = ($raw -join "`n").Trim()
        # Extract the JSON block from mixed log output
        $json = [regex]::Match($all, '\{.*\}', 'Singleline').Value
        $config = $null
        { $config = $json | ConvertFrom-Json } | Should -Not -Throw
        $config | Should -Not -BeNullOrEmpty
        $config.BaseUrl | Should -Be 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/'
    }

    It 'Respects -MaxConcurrentDownloads override' {
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
        $scriptFile = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'scripts\Install-AutoDeriva.ps1'
        Test-Path $scriptFile | Should -BeTrue
        $env:AUTODERIVA_TEST = '1'
        $raw = & $scriptFile -ShowConfig -DryRun 2>&1
        $all = ($raw -join "`n").Trim()
        $json = [regex]::Match($all, '\{.*\}', 'Singleline').Value
        $config = $json | ConvertFrom-Json
        $config | Should -Not -BeNullOrEmpty
    }
}
