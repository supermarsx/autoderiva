@echo off
set versiondrv=1.03c
set errcode=0

REM ****************************************************
REM *      COMPONENT OWNER TO UPDATE (SW_TITLE)        *
REM ****************************************************
set SW_Title=IntelBlu_XXXB2
REM ****************************************************
rem
rem Loggings of the driver uninstallation are captured for debugging purpose
rem
set Log_Folder=c:\programdata\HP\logs
if not exist "%Log_Folder%" md "%Log_Folder%"
set APP_LOG=%Log_Folder%\%SW_Title%.log

echo. >> "%APP_LOG%"
echo ^>^> %~f0 >> "%APP_LOG%"
echo ^>^> %date% %time% >> "%APP_LOG%"
echo. >> "%APP_LOG%"

echo Uninstalling "%SW_Title%"... >> "%APP_LOG%"
echo. >> "%APP_LOG%"

rem
rem At this point, the current folder is src. It's recommended to refer to any folders/files
rem under it using relative path (.\) to avoid potential space-character issues in paths.
rem

rem
rem No need to do any uninstall during preinstall
rem
if exist "c:\system.sav\tweaks" if exist "c:\system.sav\flags\Proteus.FLG" (
    echo ***INFO*** For Preinstall, the image is clean --^> skip the uninstallation here. >> "%APP_LOG%"
    goto end_UninstallDrv
)

rem
rem <TODO> Insert uninstall operations here, if any
rem Assuming that the uninstallation should not cause reboot automatically nor require reboot
rem before the installation of the new driver
REM ****************************************************


REM ****************************************************
:end_UninstallDrv

echo. >> "%APP_LOG%"
echo Done uninstalling "%SW_Title%"! >> "%APP_LOG%"

echo. >> "%APP_LOG%"
echo *exit /b %errcode% >> "%APP_LOG%"
echo. >> "%APP_LOG%"
echo ^<^< %~f0 >> "%APP_LOG%"
echo ^<^< %date% %time% >> "%APP_LOG%"
echo. >> "%APP_LOG%"

exit /b %errcode%

