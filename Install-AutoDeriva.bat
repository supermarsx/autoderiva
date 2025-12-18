@echo off
setlocal EnableExtensions

REM AutoDeriva portable one-click launcher (Windows)
REM - Downloads and runs the latest installer from GitHub
REM - Prefers Windows PowerShell 5.1 (powershell.exe) when available, falls back to PowerShell 7 (pwsh)
REM - Passes any arguments you provide through to Install-AutoDeriva.ps1
REM
REM Examples:
REM   Install-AutoDeriva.bat
REM   Install-AutoDeriva.bat -ShowConfig
REM   Install-AutoDeriva.bat -ConfigUrl https://example.com/config.json -DryRun

set "SCRIPT_URL=https://raw.githubusercontent.com/supermarsx/autoderiva/main/scripts/Install-AutoDeriva.ps1"

REM Provide repo root to the PowerShell script (used to re-launch a stable script path when elevating)
set "AUTODERIVA_REPOROOT=%~dp0"

REM If running from a repo checkout, prefer the local script instead of downloading.
if exist "%~dp0scripts\Install-AutoDeriva.ps1" (
  set "AUTODERIVA_SCRIPT_PATH=%~dp0scripts\Install-AutoDeriva.ps1"
)

REM Optional overrides (useful for CI/tests):
REM - AUTODERIVA_SCRIPT_URL: override remote URL
REM - AUTODERIVA_SCRIPT_PATH: run local script path (no network)
if defined AUTODERIVA_SCRIPT_URL set "SCRIPT_URL=%AUTODERIVA_SCRIPT_URL%"

set "PS_EXE="
where powershell >nul 2>nul && set "PS_EXE=powershell"
if not defined PS_EXE where pwsh >nul 2>nul && set "PS_EXE=pwsh"

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
set "RUN_PS1=%TMP_PS1%"
set "_AUTODERIVA_USING_TEMP=1"

REM If launched via Explorer (cmd.exe /c), keep elevated PowerShell windows open
REM so errors are visible (the installer does auto-elevation).
call :detect_pause
if defined _AUTODERIVA_PAUSE (
  set "AUTODERIVA_NOEXIT=1"
  if not defined AUTODERIVA_BAT_NOEXIT set "AUTODERIVA_BAT_NOEXIT=1"
)

if defined AUTODERIVA_BAT_DEBUG (
  echo [DEBUG] PS_EXE=%PS_EXE%
  echo [DEBUG] SCRIPT_URL=%SCRIPT_URL%
  echo [DEBUG] TMP_PS1=%TMP_PS1%
  echo [DEBUG] AUTODERIVA_REPOROOT=%AUTODERIVA_REPOROOT%
  if defined AUTODERIVA_SCRIPT_PATH echo [DEBUG] AUTODERIVA_SCRIPT_PATH=%AUTODERIVA_SCRIPT_PATH%
  if defined AUTODERIVA_NOEXIT echo [DEBUG] AUTODERIVA_NOEXIT=%AUTODERIVA_NOEXIT%
  "%PS_EXE%" -NoProfile -Command "$PSVersionTable.PSVersion.ToString(); $PSVersionTable.PSEdition" 2>nul
)

REM If a local script path is available, run it directly (no temp copy/download).
if defined AUTODERIVA_SCRIPT_PATH (
  if exist "%AUTODERIVA_SCRIPT_PATH%" (
    set "RUN_PS1=%AUTODERIVA_SCRIPT_PATH%"
    set "_AUTODERIVA_USING_TEMP=0"
  )
)

if "%_AUTODERIVA_USING_TEMP%"=="0" goto :run

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

REM Normalize encoding: strip UTF-8 BOM if present so leading comment lines are always treated as comments.
REM (Some PowerShell hosts can choke on BOM and treat the first token as "﻿#".)
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "try { $b=[System.IO.File]::ReadAllBytes($env:TMP_PS1); if ($b.Length -ge 3 -and $b[0]-eq 0xEF -and $b[1]-eq 0xBB -and $b[2]-eq 0xBF) { [System.IO.File]::WriteAllBytes($env:TMP_PS1, $b[3..($b.Length-1)]) } } catch { Write-Warning ('BOM strip failed: ' + $_.Exception.Message) }"

if defined AUTODERIVA_BAT_DEBUG (
  echo [DEBUG] First bytes of downloaded script:
  "%PS_EXE%" -NoProfile -Command "Format-Hex -Path $env:TMP_PS1 -Count 16" 2>nul
  echo [DEBUG] First line of downloaded script:
  "%PS_EXE%" -NoProfile -Command "Get-Content -LiteralPath $env:TMP_PS1 -TotalCount 1" 2>nul
)

:run

REM Optional: keep the (non-elevated) PowerShell host open after script ends.
REM NOTE: Do NOT enable this implicitly, otherwise CI/runtime tests can hang.
REM - AUTODERIVA_BAT_NOEXIT=1 forces -NoExit for the PowerShell host.
if defined AUTODERIVA_BAT_NOEXIT (
  "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -NoExit -File "%RUN_PS1%" %*
) else (
  "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%RUN_PS1%" %*
)
set "RC=%ERRORLEVEL%"
if defined AUTODERIVA_BAT_KEEP_TEMP (
  echo.
  echo NOTE: Keeping temp installer script for troubleshooting:
  echo %TMP_PS1%
) else (
  if "%_AUTODERIVA_USING_TEMP%"=="1" del "%TMP_PS1%" >nul 2>nul
)
call :maybe_pause
exit /b %RC%

:detect_pause
if defined AUTODERIVA_BAT_NO_PAUSE exit /b 0
set "_AUTODERIVA_PAUSE="
REM Heuristic: only treat as "double-clicked" when cmd.exe was spawned by Explorer.
REM This avoids CI/runtime-test hangs (they also use cmd.exe /c, but not from Explorer).
for /f "usebackq delims=" %%P in (`"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "$self=Get-CimInstance Win32_Process -Filter ('ProcessId=' + $PID); $cmdPid=$self.ParentProcessId; $cmd=Get-CimInstance Win32_Process -Filter ('ProcessId=' + $cmdPid) -ErrorAction SilentlyContinue; if(-not $cmd){''; exit 0}; $ppid=$cmd.ParentProcessId; $parent=Get-Process -Id $ppid -ErrorAction SilentlyContinue; if($parent){$parent.ProcessName}else{''}" 2^>nul`) do set "_AUTODERIVA_PARENT=%%P"
if /I "%_AUTODERIVA_PARENT%"=="explorer" set "_AUTODERIVA_PAUSE=1"
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
