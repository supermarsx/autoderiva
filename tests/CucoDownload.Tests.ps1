Describe 'Cuco download behavior' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'

        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile
    }

    AfterEach {
        $Script:Test_InvokeDownloadFile = $null

        # Best-effort cleanup of any temp dirs created by tests
        if ($script:CucoTestDir -and (Test-Path -LiteralPath $script:CucoTestDir)) {
            try { Remove-Item -LiteralPath $script:CucoTestDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
        }
        $script:CucoTestDir = $null
    }

    It 'Falls back to repo copy when the Cuco site download fails' {
        $calls = New-Object System.Collections.Generic.List[string]

        $script:CucoTestDir = Join-Path $env:TEMP ('autoderiva-cuco-test-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:CucoTestDir -Force | Out-Null

        $Config.DownloadCuco = $true
        $Config.AskBeforeDownloadCuco = $false
        $Config.CucoTargetDir = $script:CucoTestDir
        $Config.CucoPrimaryUrl = 'https://cuco.inforlandia.pt/uagent/CtoolGui.exe'
        $Config.CucoSecondaryUrl = 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/cuco/CtoolGui.exe'
        $Config.BaseUrl = 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/'
        $Config.CucoBinaryPath = 'cuco/CtoolGui.exe'
        $Config.CucoExistingFilePolicy = 'Overwrite'

        $primary = [string]$Config.CucoPrimaryUrl
        $fallback = [string]$Config.CucoSecondaryUrl

        $Script:Test_InvokeDownloadFile = {
            param($Url, $OutputPath, $MaxRetries)
            $calls.Add([string]$Url) | Out-Null

            if ($Url -like '*cuco.inforlandia.pt*') {
                return $false
            }

            $dir = Split-Path $OutputPath -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Set-Content -LiteralPath $OutputPath -Value 'dummy' -Encoding Ascii
            return $true
        }

        Install-Cuco

        $calls.Count | Should -Be 2
        $calls[0] | Should -Be $primary
        $calls[1] | Should -Be $fallback

        $outFile = Join-Path $script:CucoTestDir 'CtoolGui.exe'
        (Test-Path -LiteralPath $outFile) | Should -BeTrue
    }

    It 'Classifies primary/secondary Cuco sources as CustomUrl/GitHubRepo/None' {
        $Config.BaseUrl = 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/'
        $Config.CucoBinaryPath = 'cuco/CtoolGui.exe'
        $Config.CucoPrimaryUrl = 'https://cuco.inforlandia.pt/uagent/CtoolGui.exe'
        $Config.CucoSecondaryUrl = $null

        $info = Get-AutoDerivaCucoSourceInfo
        $info.PrimaryKind | Should -Be 'CustomUrl'
        $info.SecondaryKind | Should -Be 'GitHubRepo'

        $Config.CucoSecondaryUrl = 'none'
        $info2 = Get-AutoDerivaCucoSourceInfo
        $info2.SecondaryKind | Should -Be 'None'
    }

    It 'Allows configuring source kinds (GitHubRepo/None) directly' {
        $Config.BaseUrl = 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/'
        $Config.CucoBinaryPath = 'cuco/CtoolGui.exe'

        $Config.CucoPrimarySourceKind = 'GitHubRepo'
        $Config.CucoPrimaryUrl = 'https://example.com/ignored.exe'

        $Config.CucoSecondarySourceKind = 'None'
        $Config.CucoSecondaryUrl = 'https://example.com/ignored2.exe'

        $info = Get-AutoDerivaCucoSourceInfo
        $info.PrimaryKind | Should -Be 'GitHubRepo'
        $info.PrimaryUrl | Should -Be 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/cuco/CtoolGui.exe'
        $info.SecondaryKind | Should -Be 'None'
    }

    It 'Skips download when Cuco already exists and policy is Skip' {
        $calls = New-Object System.Collections.Generic.List[string]

        $script:CucoTestDir = Join-Path $env:TEMP ('autoderiva-cuco-test-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:CucoTestDir -Force | Out-Null
        $outFile = Join-Path $script:CucoTestDir 'CtoolGui.exe'
        Set-Content -LiteralPath $outFile -Value 'existing' -Encoding Ascii -NoNewline

        $Config.DownloadCuco = $true
        $Config.AskBeforeDownloadCuco = $false
        $Config.CucoTargetDir = $script:CucoTestDir
        $Config.CucoExistingFilePolicy = 'Skip'
        $Config.CucoPrimaryUrl = 'https://cuco.inforlandia.pt/uagent/CtoolGui.exe'
        $Config.CucoSecondaryUrl = 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/cuco/CtoolGui.exe'

        $Script:Test_InvokeDownloadFile = {
            param($Url, $OutputPath, $MaxRetries)
            $calls.Add([string]$Url) | Out-Null
            return $true
        }

        Install-Cuco

        $calls.Count | Should -Be 0
        ((Get-Content -LiteralPath $outFile -Raw).Trim()) | Should -Be 'existing'
    }

    It 'Overwrites existing Cuco when policy is Overwrite' {
        $calls = New-Object System.Collections.Generic.List[string]

        $script:CucoTestDir = Join-Path $env:TEMP ('autoderiva-cuco-test-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:CucoTestDir -Force | Out-Null
        $outFile = Join-Path $script:CucoTestDir 'CtoolGui.exe'
        Set-Content -LiteralPath $outFile -Value 'old' -Encoding Ascii -NoNewline

        $Config.DownloadCuco = $true
        $Config.AskBeforeDownloadCuco = $false
        $Config.CucoTargetDir = $script:CucoTestDir
        $Config.CucoExistingFilePolicy = 'Overwrite'
        $Config.CucoPrimaryUrl = 'https://cuco.inforlandia.pt/uagent/CtoolGui.exe'
        $Config.CucoSecondaryUrl = 'https://raw.githubusercontent.com/supermarsx/autoderiva/main/cuco/CtoolGui.exe'

        $Script:Test_InvokeDownloadFile = {
            param($Url, $OutputPath, $MaxRetries)
            $calls.Add([string]$Url) | Out-Null
            $dir = Split-Path $OutputPath -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Set-Content -LiteralPath $OutputPath -Value 'new' -Encoding Ascii -NoNewline
            return $true
        }

        Install-Cuco

        $calls.Count | Should -BeGreaterThan 0
        ((Get-Content -LiteralPath $outFile -Raw).Trim()) | Should -Be 'new'
    }
}
