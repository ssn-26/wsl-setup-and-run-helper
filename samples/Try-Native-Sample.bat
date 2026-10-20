:: Opens the NATIVE (WPF) sample of the new WSL Control Panel window (fake data -
:: nothing in WSL is touched).
@echo off
setlocal
set "PS1=%~dp0native\Sample.ps1"
if not exist "%PS1%" (
    echo  Error: native\Sample.ps1 was not found next to this file.
    pause
    exit /b 1
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%PS1%"
endlocal
