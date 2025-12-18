[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Format', 'Lint', 'Test', 'All')]
    [string]$Mode = 'All',

    [Parameter()]
    [string]$BatPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'Install-AutoDeriva.bat')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-BatFormatCheck {
    param([string]$Path)

    Assert-True (Test-Path -LiteralPath $Path) "BAT not found: $Path"

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding Byte
    Assert-True ($raw.Length -gt 0) 'BAT is empty.'

    # Ensure no UTF-16 / null bytes
    Assert-True (-not ($raw -contains 0)) 'BAT appears to contain NUL bytes (unexpected encoding like UTF-16). Save as ANSI/UTF-8 (no NULs).'

    $text = [System.Text.Encoding]::UTF8.GetString($raw)

    # Enforce CRLF (no lone \n)
    $hasLf = $text.Contains("`n")
    Assert-True $hasLf 'BAT has no newlines?'

    $loneLf = [regex]::IsMatch($text, "(?<!`r)`n")
    Assert-True (-not $loneLf) 'BAT contains LF-only line endings. Use CRLF for .bat files.'

    # No tabs
    Assert-True (-not $text.Contains("`t")) 'BAT contains TAB characters. Use spaces.'

    # No trailing whitespace on lines
    $lines = $text -split "`r`n", -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match "[ \t]+$") {
            throw "BAT has trailing whitespace on line $($i + 1)."
        }
    }
}

function Invoke-BatLintCheck {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

    Assert-True ($text -match "(?m)^@echo off\s*$") 'BAT must start with @echo off.'
    Assert-True ($text -match "(?m)^setlocal EnableExtensions\s*$") 'BAT must use setlocal EnableExtensions.'

    Assert-True ($text -match "(?m)^set \"SCRIPT_URL=https://raw\.githubusercontent\.com/supermarsx/autoderiva/main/scripts/Install-AutoDeriva\.ps1\"\s*$") 'BAT SCRIPT_URL must point to main scripts/Install-AutoDeriva.ps1 raw URL.'

    Assert-True ($text -match "(?m)%\*\s*$") 'BAT must forward args using %*.'
    Assert-True ($text -match "(?m)^exit /b %ERRORLEVEL%\s*$") 'BAT must exit with %ERRORLEVEL%.'

    # Ensure we keep the documented behavior of downloading and invoking script content.
    Assert-True ($text -match "ScriptBlock\]::Create") 'BAT must use ScriptBlock::Create invocation pattern.'
}

function Invoke-BatRuntimeTest {
    param([string]$Path)

    Assert-True (Test-Path -LiteralPath $Path) "BAT not found: $Path"

    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $localScriptPath = Join-Path $repoRoot 'scripts\Install-AutoDeriva.ps1'
    Assert-True (Test-Path -LiteralPath $localScriptPath) "Local script missing: $localScriptPath"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.WorkingDirectory = $repoRoot
    $psi.Arguments = "/c \"\"$Path\" -ShowConfig\""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    # Make the BAT use local installer (no network) and make the PS installer test-safe.
    $psi.Environment['AUTODERIVA_TEST'] = '1'
    $psi.Environment['AUTODERIVA_SCRIPT_PATH'] = $localScriptPath

    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($p.ExitCode -ne 0) {
        throw "BAT runtime test failed with exit code $($p.ExitCode). STDERR: $stderr"
    }

    if ($stdout -notmatch 'AUTODERIVA::CONFIG::') {
        throw "BAT runtime test did not output AUTODERIVA::CONFIG::. Output was: $stdout"
    }
}

$Mode = $Mode.Trim()

if ($Mode -in @('Format', 'All')) {
    Write-Host 'Batch: format check...' -ForegroundColor Cyan
    Invoke-BatFormatCheck -Path $BatPath
    Write-Host 'Batch: format check OK' -ForegroundColor Green
}

if ($Mode -in @('Lint', 'All')) {
    Write-Host 'Batch: lint check...' -ForegroundColor Cyan
    Invoke-BatLintCheck -Path $BatPath
    Write-Host 'Batch: lint check OK' -ForegroundColor Green
}

if ($Mode -in @('Test', 'All')) {
    Write-Host 'Batch: runtime test...' -ForegroundColor Cyan
    Invoke-BatRuntimeTest -Path $BatPath
    Write-Host 'Batch: runtime test OK' -ForegroundColor Green
}
