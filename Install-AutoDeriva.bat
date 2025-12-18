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
  call :maybe_pause
  exit /b 1
)

REM NOTE: A literal `irm ... | iex` pattern doesn't support forwarding script parameters.
REM This approach preserves argument forwarding reliably (even for args starting with '-'):
REM  1) Download/copy the installer to a temp .ps1
REM  2) Invoke PowerShell with -File <temp.ps1> %*
set "TMP_PS1=%TEMP%\AutoDeriva_Install_%RANDOM%%RANDOM%.ps1"

REM If launched via Explorer (cmd.exe /c), keep elevated PowerShell windows open
REM so errors are visible (the installer does auto-elevation).
call :detect_pause
if defined _AUTODERIVA_PAUSE set "AUTODERIVA_NOEXIT=1"

if defined AUTODERIVA_BAT_DEBUG (
  echo [DEBUG] PS_EXE=%PS_EXE%
  echo [DEBUG] SCRIPT_URL=%SCRIPT_URL%
  echo [DEBUG] TMP_PS1=%TMP_PS1%
  if defined AUTODERIVA_NOEXIT echo [DEBUG] AUTODERIVA_NOEXIT=%AUTODERIVA_NOEXIT%
  "%PS_EXE%" -NoProfile -Command "$PSVersionTable.PSVersion.ToString(); $PSVersionTable.PSEdition" 2>nul
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; $u='%SCRIPT_URL%'; $p=$env:AUTODERIVA_SCRIPT_PATH; $out=$env:TMP_PS1; if (-not $out) { throw 'TMP_PS1 not set' }; if ($p -and (Test-Path -LiteralPath $p)) { Copy-Item -LiteralPath $p -Destination $out -Force } else { Invoke-WebRequest -Uri $u -OutFile $out -UseBasicParsing -ErrorAction Stop } } catch { Write-Error $_; exit 1 }"
if not %ERRORLEVEL%==0 (
  echo ERROR: Failed to download/copy installer script.
  echo - SCRIPT_URL=%SCRIPT_URL%
  echo - TMP_PS1=%TMP_PS1%
  if defined AUTODERIVA_BAT_DEBUG "%PS_EXE%" -NoProfile -Command "if (Test-Path -LiteralPath $env:TMP_PS1) { Format-Hex -Path $env:TMP_PS1 -Count 16 } else { 'no temp file created' }" 2>nul
  del "%TMP_PS1%" >nul 2>nul
  call :maybe_pause
  exit /b %ERRORLEVEL%
)

if defined AUTODERIVA_BAT_DEBUG (
  echo [DEBUG] First bytes of downloaded script:
  "%PS_EXE%" -NoProfile -Command "Format-Hex -Path $env:TMP_PS1 -Count 16" 2>nul
  echo [DEBUG] First line of downloaded script:
  "%PS_EXE%" -NoProfile -Command "Get-Content -LiteralPath $env:TMP_PS1 -TotalCount 1" 2>nul
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%TMP_PS1%" %*
set "RC=%ERRORLEVEL%"
if defined AUTODERIVA_BAT_KEEP_TEMP (
  echo.
  echo NOTE: Keeping temp installer script for troubleshooting:
  echo %TMP_PS1%
) else (
  del "%TMP_PS1%" >nul 2>nul
)
call :maybe_pause
exit /b %RC%

:detect_pause
if defined AUTODERIVA_BAT_NO_PAUSE exit /b 0
set "_AUTODERIVA_PAUSE="
echo %cmdcmdline% | find /I "/c" >nul 2>nul && set "_AUTODERIVA_PAUSE=1"
if defined AUTODERIVA_BAT_PAUSE set "_AUTODERIVA_PAUSE=1"
exit /b 0

:maybe_pause
REM Keep the window open when started via Explorer (cmd.exe /c) so errors/output are visible.
REM - Set AUTODERIVA_BAT_PAUSE=1 to force pausing.
REM - Set AUTODERIVA_BAT_NO_PAUSE=1 to disable pausing.
if defined AUTODERIVA_BAT_NO_PAUSE exit /b 0

call :detect_pause

if defined _AUTODERIVA_PAUSE (
  echo.
  echo Press any key to close...
  pause >nul
)
exit /b 0
