:: ================================================================
:: WSL Control Panel - double-click this to install (or update) the panel
:: from this folder. Same as: right-click install.ps1 > Run with PowerShell.
:: No administrator rights needed. Keep this file CRLF.
:: ================================================================
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
