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
REM This approach preserves argument forwarding reliably (even for args starting with '-'):
REM  1) Download/copy the installer to a temp .ps1
REM  2) Invoke PowerShell with -File <temp.ps1> %*
set "TMP_PS1=%TEMP%\AutoDeriva_Install_%RANDOM%%RANDOM%.ps1"

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; $u='%SCRIPT_URL%'; $p=$env:AUTODERIVA_SCRIPT_PATH; $out=$env:TMP_PS1; if (-not $out) { throw 'TMP_PS1 not set' }; if ($p -and (Test-Path -LiteralPath $p)) { Copy-Item -LiteralPath $p -Destination $out -Force } else { Invoke-WebRequest -Uri $u -OutFile $out -UseBasicParsing -ErrorAction Stop } } catch { Write-Error $_; exit 1 }"
if not %ERRORLEVEL%==0 (
  del "%TMP_PS1%" >nul 2>nul
  exit /b %ERRORLEVEL%
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%TMP_PS1%" %*
set "RC=%ERRORLEVEL%"
del "%TMP_PS1%" >nul 2>nul
exit /b %RC%
