@echo off
setlocal EnableExtensions

REM AutoDeriva portable one-click launcher (Windows)
REM - Downloads and runs the latest installer from GitHub
REM - Prefers PowerShell 7 (pwsh) when available, falls back to Windows PowerShell
REM - Passes any arguments you provide through to Install-AutoDeriva.ps1
REM
REM Examples:
REM   Install-AutoDeriva.bat
REM   Install-AutoDeriva.bat -ShowConfig
REM   Install-AutoDeriva.bat -ConfigUrl https://example.com/config.json -DryRun

set "SCRIPT_URL=https://raw.githubusercontent.com/supermarsx/autoderiva/main/scripts/Install-AutoDeriva.ps1"

REM Optional overrides (useful for CI/tests):
REM - AUTODERIVA_SCRIPT_URL: override remote URL
REM - AUTODERIVA_SCRIPT_PATH: run local script path (no network)
if defined AUTODERIVA_SCRIPT_URL set "SCRIPT_URL=%AUTODERIVA_SCRIPT_URL%"

set "PS_EXE="
where pwsh >nul 2>nul && set "PS_EXE=pwsh"
if not defined PS_EXE where powershell >nul 2>nul && set "PS_EXE=powershell"

if not defined PS_EXE (
  echo ERROR: PowerShell was not found. Please install PowerShell and try again.
  echo - Windows PowerShell is normally available on Windows.
  echo - PowerShell 7+ can be installed from https://aka.ms/powershell
  exit /b 1
)

REM NOTE: A literal `irm ... | iex` pattern doesn't support forwarding script parameters.
REM This is the closest equivalent: load script text (from local file or via `irm`), then invoke the scriptblock with @args.
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; $u='%SCRIPT_URL%'; $p=$env:AUTODERIVA_SCRIPT_PATH; if ($p -and (Test-Path -LiteralPath $p)) { $s = Get-Content -LiteralPath $p -Raw } else { $s = [string](irm -Uri $u) }; & ([ScriptBlock]::Create([string]$s)) @args } catch { Write-Error $_; exit 1 }" --% %*
exit /b %ERRORLEVEL%
