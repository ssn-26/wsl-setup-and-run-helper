:: ================================================================
:: WSL Control Panel - start file. Double-click this to open the panel.
::
:: Opens the window (powershell\WSL-Control-Panel.ps1). For no console window
:: and no security warnings, install it instead (see install.ps1 / README).
:: Keep this file CRLF (Windows line endings).
:: ================================================================
@echo off
setlocal

set "PS_SCRIPT=%~dp0powershell\WSL-Control-Panel.ps1"
if not exist "%PS_SCRIPT%" (
    echo.
    echo  Error: powershell\WSL-Control-Panel.ps1 was not found in "%~dp0"
    echo  Keep this .bat together with the "powershell" and "bash" folders.
    echo.
    pause
    exit /b 1
)

:: Installed with install.ps1: start the app itself (no console window at all).
if exist "%~dp0WSL Control Panel.exe" (
    start "" "%~dp0WSL Control Panel.exe"
    exit /b 0
)

:: -STA: the window needs it. Errors show in a message box from the panel.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%PS_SCRIPT%"
endlocal
