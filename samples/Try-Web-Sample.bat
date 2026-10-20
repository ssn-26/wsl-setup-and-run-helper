:: Opens the WEB-STYLE sample of the new WSL Control Panel window (fake data -
:: nothing in WSL is touched). Uses Edge in "app mode": its own window, no tabs.
@echo off
setlocal
set "PAGE=%~dp0web\index.html"
if not exist "%PAGE%" (
    echo  Error: web\index.html was not found next to this file.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$u = [Uri]::new($env:PAGE).AbsoluteUri; try { Start-Process msedge -ArgumentList ('--app=' + $u), '--window-size=1280,820' -ErrorAction Stop } catch { Start-Process $u }"
endlocal
