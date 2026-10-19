:: ================================================================
:: WSL Control Panel - launcher. Double-click this to open the panel.
::
:: Thin launcher for WSL-Control-Panel.ps1, which holds all the logic.
:: Keep this file CRLF (Windows line endings).
:: ================================================================
@echo off
setlocal
title WSL Control Panel

set "PS_SCRIPT=%~dp0WSL-Control-Panel.ps1"
if not exist "%PS_SCRIPT%" (
    echo.
    echo  Error: WSL-Control-Panel.ps1 was not found in "%~dp0"
    echo  Keep the .bat, the .ps1 and the "scripts" folder together.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "RC=%errorlevel%"
if not "%RC%"=="0" (
    echo.
    echo  The panel stopped with an error ^(code %RC%^). Read the message above.
    pause
)
endlocal
exit /b %RC%
