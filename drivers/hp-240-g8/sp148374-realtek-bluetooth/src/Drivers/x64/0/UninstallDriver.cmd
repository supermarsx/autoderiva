@echo off
setlocal enabledelayedexpansion

:: BatchGotAdmin
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
:--------------------------------------

echo **************************************************************
echo ***  Batch Uninstall Realtek Bluetooth Filter Driver               
echo ***                                                            
echo ***  Please wait a moment	                  
echo=

if %PROCESSOR_ARCHITECTURE%==AMD64 (
    set BTDIR="C:\Program Files (x86)\REALTEK\Realtek Bluetooth"
)
if %PROCESSOR_ARCHITECTURE%==x86 (
    set BTDIR="C:\Program Files\REALTEK\Realtek Bluetooth"
)


set var=%BTDIR:~1,-1%

::"%var%\dpinst.exe" /Q /D /U "%var%\Rtkfilter.inf"
powershell -ExecutionPolicy Bypass -File %~dp0script.ps1 unin 

sc stop RtkBtManServ
sc delete RtkBtManServ

rd /q /s %BTDIR%

del %WINDIR%\System32\drivers\RtkBtfilter.sys
del %WINDIR%\rtl8723b_mp_chip_bt40_fw_asic_rom_patch_new
del %WINDIR%\rtl8723b_mp_chip_bt40_fw_asic_rom_patch_new_s1
del %WINDIR%\rtl8723d_mp_chip_bt40_fw_asic_rom_patch_new
del %WINDIR%\rtl8821c_mp_chip_bt40_fw_asic_rom_patch_new
del %WINDIR%\rtl8822b_mp_chip_bt40_fw_asic_rom_patch_new
del %WINDIR%\rtl8822c_mp_chip_bt40_fw_asic_rom_patch_new
del %WINDIR%\rtl8852a_mp_chip_bt40_fw_asic_rom_patch_new
del %WINDIR%\rtl8852b_mp_chip_bt40_fw_asic_rom_patch_new
del %WINDIR%\rtl8852c_mp_chip_bt40_fw_asic_rom_patch_new
del %WINDIR%\rtl8851b_mp_chip_bt40_fw_asic_rom_patch_new

ping -n 3 127.0.0.1>nul
del /F %WINDIR%\RtkBtManServ.exe


echo=
echo **************************************************************
echo ***  Driver Uninstall Finished              
echo ***                                                            
echo ***  Please restart your unit after installation finished                  
echo=
