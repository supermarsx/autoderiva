Describe 'SHA256 verification (installer helpers)' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'

        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile

        # Ensure verification is enabled for these tests
        $Config.VerifyFileHashes = $true
        $Config.HashVerifyMode = 'Parallel'
        $Config.HashVerifyMaxConcurrency = 5
        $Config.DeleteFilesOnHashMismatch = $false
    }

    It 'computes a stable SHA256 hex for a file' {
        $path = Join-Path $env:TEMP ("autoderiva_sha_test_" + [guid]::NewGuid().ToString('N') + '.txt')
        try {
            Set-Content -LiteralPath $path -Value 'hello' -NoNewline -Encoding UTF8
            $h1 = Get-AutoDerivaSha256Hex -Path $path
            $h2 = Get-AutoDerivaSha256Hex -Path $path

            $h1 | Should -Match '^[0-9a-f]{64}$'
            $h2 | Should -Be $h1
        }
        finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'skips verification when ExpectedSha256 is missing (no throw)' {
        $Script:Stats.FilesDownloadFailed = 0
        $Script:Stats.FilesDownloaded = 0

        $tempFile = Join-Path $env:TEMP ("autoderiva_sha_skip_" + [guid]::NewGuid().ToString('N') + '.bin')
        try {
            Set-Content -LiteralPath $tempFile -Value 'data' -NoNewline -Encoding UTF8
            $fileList = @(
                @{ OutputPath = $tempFile; RelativePath = 'x.bin' }
            )

            { Invoke-DownloadedFileHashVerification -FileList $fileList } | Should -Not -Throw
            Test-Path -LiteralPath $tempFile | Should -BeTrue
            $Script:Stats.FilesDownloadFailed | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It 'warns and keeps file on SHA256 mismatch by default (Single mode)' {
        $Config.HashVerifyMode = 'Single'
        $Config.DeleteFilesOnHashMismatch = $false
        $Script:Stats.FilesDownloadFailed = 0
        $Script:Stats.FilesDownloaded = 1

        $tempFile = Join-Path $env:TEMP ("autoderiva_sha_mismatch_" + [guid]::NewGuid().ToString('N') + '.bin')
        try {
            Set-Content -LiteralPath $tempFile -Value 'data' -NoNewline -Encoding UTF8
            $badExpected = ('0' * 64)

            $fileList = @(
                @{ OutputPath = $tempFile; RelativePath = 'mismatch.bin'; ExpectedSha256 = $badExpected }
            )

            { Invoke-DownloadedFileHashVerification -FileList $fileList } | Should -Not -Throw
            Test-Path -LiteralPath $tempFile | Should -BeTrue
            $Script:Stats.FilesDownloadFailed | Should -Be 1
        }
        finally {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It 'deletes file when DeleteFilesOnHashMismatch is true' {
        $Config.HashVerifyMode = 'Single'
        $Config.DeleteFilesOnHashMismatch = $true
        $Script:Stats.FilesDownloadFailed = 0
        $Script:Stats.FilesDownloaded = 1

        $tempFile = Join-Path $env:TEMP ("autoderiva_sha_delete_" + [guid]::NewGuid().ToString('N') + '.bin')
        try {
            Set-Content -LiteralPath $tempFile -Value 'data' -NoNewline -Encoding UTF8
            $badExpected = ('0' * 64)

            $fileList = @(
                @{ OutputPath = $tempFile; RelativePath = 'delete.bin'; ExpectedSha256 = $badExpected }
            )

            { Invoke-DownloadedFileHashVerification -FileList $fileList } | Should -Not -Throw
            Test-Path -LiteralPath $tempFile | Should -BeFalse
            $Script:Stats.FilesDownloadFailed | Should -Be 1
        }
        finally {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It 'treats invalid ExpectedSha256 as failure (no crash)' {
        $Config.HashVerifyMode = 'Single'
        $Config.DeleteFilesOnHashMismatch = $true
        $Script:Stats.FilesDownloadFailed = 0
        $Script:Stats.FilesDownloaded = 1

        $tempFile = Join-Path $env:TEMP ("autoderiva_sha_invalid_" + [guid]::NewGuid().ToString('N') + '.bin')
        try {
            Set-Content -LiteralPath $tempFile -Value 'data' -NoNewline -Encoding UTF8
            $fileList = @(
                @{ OutputPath = $tempFile; RelativePath = 'invalid.bin'; ExpectedSha256 = 'NOT_A_SHA' }
            )

            { Invoke-DownloadedFileHashVerification -FileList $fileList } | Should -Not -Throw
            Test-Path -LiteralPath $tempFile | Should -BeFalse
            $Script:Stats.FilesDownloadFailed | Should -Be 1
        }
        finally {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It 'falls back from Parallel to Single when runspace pooling fails (no crash)' {
        $Config.HashVerifyMode = 'Parallel'
        $Config.HashVerifyMaxConcurrency = 5
        $Config.DeleteFilesOnHashMismatch = $false

        $Script:Stats.FilesDownloadFailed = 0
        $Script:Stats.FilesDownloaded = 1

        $tempFile = Join-Path $env:TEMP ("autoderiva_sha_fallback_" + [guid]::NewGuid().ToString('N') + '.bin')
        try {
            Set-Content -LiteralPath $tempFile -Value 'data' -NoNewline -Encoding UTF8
            $expected = (Get-AutoDerivaSha256Hex -Path $tempFile)

            $fileList = @(
                @{ OutputPath = $tempFile; RelativePath = 'fallback.bin'; ExpectedSha256 = $expected }
            )

            $Script:Test_FailHashRunspacePool = $true
            { Invoke-DownloadedFileHashVerification -FileList $fileList } | Should -Not -Throw
            Test-Path -LiteralPath $tempFile | Should -BeTrue
            $Script:Stats.FilesDownloadFailed | Should -Be 0
        }
        finally {
            $Script:Test_FailHashRunspacePool = $false
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It 'skips driver installation when HashMismatchPolicy=SkipDriver' {
        $env:AUTODERIVA_TEST = '1'
        $Config.VerifyFileHashes = $true
        $Config.DeleteFilesOnHashMismatch = $false
        $Config.HashVerifyMode = 'Single'
        $Config.HashMismatchPolicy = 'SkipDriver'
        $Script:DryRun = $true

        $tempDir = Join-Path $env:TEMP ("autoderiva_policy_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        try {
            $inf = 'drivers/test/oem1.inf'
            $rel = 'drivers/test/file.bin'
            $outPath = Join-Path $tempDir ($rel -replace '/', '\\')
            New-Item -ItemType Directory -Path (Split-Path $outPath -Parent) -Force | Out-Null
            Set-Content -LiteralPath $outPath -Value 'data' -NoNewline -Encoding UTF8

            $badExpected = ('0' * 64)

            $Script:Test_GetRemoteCsv = {
                param($Url)
                @(
                    [pscustomobject]@{ RelativePath = 'drivers/test/file.bin'; AssociatedInf = 'drivers/test/oem1.inf'; Sha256 = $badExpected }
                )
            }

            $Script:Test_InvokeConcurrentDownload = {
                param($FileList, $MaxConcurrency, $TestMode)
                # no-op: file already exists
                return
            }

            $driver = [pscustomobject]@{ InfPath = $inf; HardwareIDs = 'PCI\\VEN_TEST&DEV_TEST' }
            $res = Install-Driver -DriverMatches @($driver) -TempDir $tempDir

            $res | Should -Not -BeNullOrEmpty
            ($res | Where-Object { $_.Driver -eq $inf -and $_.Status -eq 'Skipped (Hash Mismatch)' }).Count | Should -Be 1
        }
        finally {
            $Script:Test_GetRemoteCsv = $null
            $Script:Test_InvokeConcurrentDownload = $null
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
