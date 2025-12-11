cd %~dp0

@echo off
REM Set you log name and path here.
Set Logpath=C:\system.sav\Logs\Softpaq_install.log
if not exist C:\system.sav\Logs md C:\system.sav\Logs
REM  Detect OS version
set os_ver=
for /f "tokens=1,2 delims== " %%i in ('wmic os get version /value') do (if /i %%~i == version set "os_ver=%%~j")
if not defined os_ver echo [%date%][%time%][%~dpnx0] Could not get OS version >> %Logpath% & goto fail
ECHO [%date%][%time%][%~dpnx0] Detected OS version : [%os_ver%] >> %Logpath%

pushd Drivers
rem install your driver here pnputil -i -a
"installdrv.cmd"
rem pnputil -i -a xxxxComponentxxx.inf
rem after driver install
popd

:fail
goto END

:unsupport_OS
mshta.exe vbscript:Execute("msgbox ""The driver is not supported on this OS version (%os_ver%)."",48,""Warning"":close")
:END