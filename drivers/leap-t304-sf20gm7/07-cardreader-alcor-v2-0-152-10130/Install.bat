@echo off

: BatchGotAdmin
:-------------------------------------
REM  --> Check for permissions
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

REM --> If error flag set, we do not have admin.
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"

    wscript "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"
:---------------------------------------------------------------------------

cd /d "%~dp0"

for /r %%i in (*.inf) do pnputil -i -a "%%i"
if not %errorlevel% == 0 if not %errorlevel% == 259 goto fail

:pass
timeout /t 10
goto end

:fail
echo.
echo.
echo Admin privileges are required to perform this driver installation.
echo Right-click this installation file and select "Run as Administrator"!
pause

:end