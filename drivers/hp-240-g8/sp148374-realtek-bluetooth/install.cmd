echo off
REM The following is required in all INSTALL.CMD files
if exist c:\system.sav\util\SetVariables.cmd Call c:\system.sav\util\SetVariables.cmd
set version=1.03c
Set block=%~dp0
CD /D "%block%"
REM Remove the REM from the next line if your component does not support Silent Install (Application Recovery)
REM Erase /F /Q *.CVA
REM Add the command-line to have your component to be installed properly

Pushd src
if not defined FCC_LOG_FOLDER goto BPS
call "%~dp0src\InstallDrv.cmd"
goto :END

:BPS
if exist "%~dp0src\Uninstall.cmd" call "%~dp0src\Uninstall.cmd"
if %errorlevel% NEQ 0 goto :END
if exist "%~dp0src\InstallDrv.cmd" call "%~dp0src\InstallDrv.cmd"
if %errorlevel% NEQ 0 goto :END
if exist "%~dp0src\UWP\appxinst.cmd" call "%~dp0src\UWP\appxinst.cmd"

:END
Popd
REM Erase failure flag file when install succeeded. Most applications return zero to indicate success.
EXIT /B %ERRORLEVEL%

