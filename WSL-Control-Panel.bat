:: ================================================================
:: WSL Control Panel - start file. Double-click this to open the panel.
::
:: Thin launcher for powershell\WSL-Control-Panel.ps1, which holds the logic.
:: Keep this file CRLF (Windows line endings).
:: ================================================================
@echo off
setlocal
title WSL Control Panel

set "PS_SCRIPT=%~dp0powershell\WSL-Control-Panel.ps1"
if not exist "%PS_SCRIPT%" (
    echo.
    echo  Error: powershell\WSL-Control-Panel.ps1 was not found in "%~dp0"
    echo  Keep this .bat together with the "powershell" and "bash" folders.
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
