:: ================================================================
::  WSL / Ubuntu Control Panel
::  List, open (with saved accounts), close, delete, download distros.
::  Passwords are stored ENCRYPTED with Windows DPAPI, never plain text.
::  Lines starting with REM or :: are comments (ignored by Windows).
:: ================================================================

@echo off
setlocal enabledelayedexpansion
set WSL_UTF8=1
title WSL / Ubuntu Control Panel

REM  ============================ CONFIG ============================
REM  Where newly downloaded distros are installed. Change this one line
REM  if you don't have a D: drive (e.g. C:\WSL). The folder is created
REM  automatically. Saved accounts always live next to THIS file.
set "WSL_BASE=D:\Linux\WSL"
REM  ===============================================================

REM  First run of all: make sure WSL itself is installed on Windows before we
REM  ever show the panel. A brand-new PC has no WSL at all - this bootstraps it.
goto CHECK_WSL


:CHECK_WSL
REM  Is a working, modern WSL present?  "wsl --version" prints the WSL version
REM  and exits 0 only when the real (Store) WSL platform is installed. On a PC
REM  where WSL was never set up, wsl.exe is just a stub and this call fails,
REM  so we send the user into the guided one-time setup.
where wsl >nul 2>&1 || goto SETUP_WSL
wsl --version >nul 2>&1 || goto SETUP_WSL
goto MAIN


:SETUP_WSL
cls
echo ================================================================
echo               First-time setup - installing WSL
echo ================================================================
echo.
echo  WSL (Windows Subsystem for Linux) is not set up on this PC yet.
echo  This is the one-time step that lets you run Linux on Windows.
echo.
echo  What will happen:
echo    1. A Windows security prompt (UAC) asks for administrator rights
echo       - click YES. This is required to turn WSL on.
echo    2. Windows turns on the needed features and downloads WSL.
echo    3. If Windows says a RESTART is required, restart your PC, then
echo       run this panel again - it will pick up where it left off and
echo       let you download a Linux distro.
echo.
echo  Nothing on your D: drive or elsewhere is deleted by this step.
echo.
set "go="
set /p "go=Set up WSL now? (Y/N): "
if /i not "!go!"=="Y" goto END

REM  Build a tiny elevated helper script. The install/enable-feature commands
REM  need administrator rights, so we run THIS script "as administrator" via a
REM  UAC prompt while the panel itself stays a normal window.
set "SETUPBAT=%TEMP%\wsl-first-time-setup.bat"
> "%SETUPBAT%" echo @echo off
>> "%SETUPBAT%" echo set WSL_UTF8=1
>> "%SETUPBAT%" echo title Installing WSL - please wait
>> "%SETUPBAT%" echo echo ================================================================
>> "%SETUPBAT%" echo echo   Installing WSL  ^(administrator^)
>> "%SETUPBAT%" echo echo ================================================================
>> "%SETUPBAT%" echo echo.
>> "%SETUPBAT%" echo echo Turning on the Windows features WSL needs ^(safe if already on^)...
>> "%SETUPBAT%" echo dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
>> "%SETUPBAT%" echo dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
>> "%SETUPBAT%" echo echo.
>> "%SETUPBAT%" echo echo Installing the WSL platform ^(no Linux distro yet^)...
>> "%SETUPBAT%" echo wsl --install --no-distribution
>> "%SETUPBAT%" echo echo.
>> "%SETUPBAT%" echo echo Fetching the latest WSL update...
>> "%SETUPBAT%" echo wsl --update
>> "%SETUPBAT%" echo wsl --set-default-version 2
>> "%SETUPBAT%" echo echo.
>> "%SETUPBAT%" echo echo ================================================================
>> "%SETUPBAT%" echo echo   If you see a message above about a RESTART being required,
>> "%SETUPBAT%" echo echo   restart Windows now, then run the WSL Control Panel again.
>> "%SETUPBAT%" echo echo ================================================================
>> "%SETUPBAT%" echo echo.
>> "%SETUPBAT%" echo pause

echo.
echo  Asking for administrator rights - please click YES on the prompt...
powershell -NoProfile -Command "Start-Process -Verb RunAs -Wait -FilePath '%SETUPBAT%'"
del "%SETUPBAT%" >nul 2>&1

echo.
echo  Checking whether WSL is ready...
wsl --version >nul 2>&1
if not errorlevel 1 (
    echo.
    echo  WSL is installed and ready. Continuing to the control panel,
    echo  where you can download a Linux distro with the [N] option.
    echo.
    pause >nul
    goto MAIN
)
echo.
echo  WSL was set up but Windows needs a RESTART to finish enabling it.
echo    1. Restart your PC.
echo    2. Run this WSL Control Panel again.
echo    3. Use [N] to download your first Linux distro.
echo.
pause >nul
goto END


:MAIN
cls
echo ================================================================
echo                   WSL / Ubuntu Control Panel
echo ================================================================
echo.
echo  Your installed distros and their state:
echo  ----------------------------------------------------------------
wsl --list --verbose
echo  ----------------------------------------------------------------
echo.
set count=0
for /f "usebackq delims=" %%d in (`wsl --list --quiet`) do (
    set /a count+=1
    set "distro[!count!]=%%d"
)
echo  Just press ENTER to quick-open your desktop (wakes it first), or:
echo.
echo  Pick a distro by number:
for /l %%i in (1,1,!count!) do echo     [%%i] !distro[%%i]!
echo.
echo     [C] Close a running distro
echo     [S] Shut down ALL WSL / free memory
echo     [N] Download / install a NEW distro
echo     [U] Update / repair WSL itself
echo     [Q] Quit
echo.
set "choice="
set /p "choice=Enter your choice: "
if not defined choice goto QUICK
if /i "!choice!"=="Q" goto END
if /i "!choice!"=="C" goto CLOSE_MENU
if /i "!choice!"=="S" goto SHUTDOWN_ALL
if /i "!choice!"=="N" goto DOWNLOAD
if /i "!choice!"=="U" goto UPDATE_WSL
if defined distro[!choice!] (
    for %%c in (!choice!) do set "sel=!distro[%%c]!"
    goto DISTRO_MENU
)
echo.
echo  That was not a valid choice. Press any key to try again.
pause >nul
goto MAIN


:QUICK
REM  One-click path: wake and open the FIRST distro's desktop, auto-using
REM  the first saved account (if any). This is the integrated one-click launcher.
if not defined distro[1] (
    echo  No distros installed.
    pause >nul
    goto MAIN
)
set "sel=!distro[1]!"
set "acctuser="
set "acctblob="
set "afile=%~dp0accounts\!sel!.acct"
if exist "!afile!" (
    for /f "usebackq tokens=1,2 delims=," %%u in ("!afile!") do if not defined acctuser (
        set "acctuser=%%u"
        set "acctblob=%%v"
    )
)
goto OPEN_DESKTOP


:CLOSE_MENU
cls
echo ================================================================
echo                   Close a running distro
echo ================================================================
echo.
set rcount=0
for /f "usebackq delims=" %%r in (`wsl --list --running --quiet`) do (
    set /a rcount+=1
    set "run[!rcount!]=%%r"
)
if !rcount!==0 (
    echo  No distros are currently running - nothing to close.
    echo.
    pause >nul
    goto MAIN
)
echo  Currently running:
for /l %%i in (1,1,!rcount!) do echo     [%%i] !run[%%i]!
echo.
echo     [A] Close ALL running distros
echo     [B] Back
echo.
set "rc="
set /p "rc=Which to close: "
if /i "!rc!"=="B" goto MAIN
if /i "!rc!"=="A" goto CLOSE_ALL
if defined run[!rc!] (
    for %%c in (!rc!) do set "target=!run[%%c]!"
    echo.
    echo  Shutting down !target! ...
    call :STOP_KEX "!target!"
    wsl --terminate !target!
    call :FREEVM
    echo  Done - !target! is now stopped.
    pause >nul
    goto CLOSE_MENU
)
echo.
echo  Invalid choice. Press any key.
pause >nul
goto CLOSE_MENU

:CLOSE_ALL
echo.
echo  Shutting down ALL running distros...
call :STOP_KEX_ALL
wsl --shutdown
echo  Done - everything is stopped.
pause >nul
goto MAIN


:DISTRO_MENU
cls
set "state=STOPPED"
for /f "usebackq delims=" %%r in (`wsl --list --running --quiet`) do if /i "%%r"=="!sel!" set "state=RUNNING"
echo ================================================================
echo   Selected distro:   !sel!
echo   State:             !state!
echo ================================================================
echo.
echo     [O] Open this distro
if "!state!"=="RUNNING" echo     [C] Close (shut down) this distro
echo     [D] Delete this distro   (permanent!)
echo     [B] Back to the list
echo.
set "act="
set /p "act=Enter your choice: "
if /i "!act!"=="O" goto OPEN
if /i "!act!"=="C" goto CLOSE_ONE
if /i "!act!"=="D" goto DELETE
if /i "!act!"=="B" goto MAIN
echo  Invalid choice. Press any key.
pause >nul
goto DISTRO_MENU


:CLOSE_ONE
if "!state!"=="STOPPED" (
    echo.
    echo  !sel! is already stopped.
    pause >nul
    goto DISTRO_MENU
)
echo.
echo  Shutting down !sel! ...
call :STOP_KEX "!sel!"
wsl --terminate !sel!
call :FREEVM
echo  Done - !sel! is now stopped.
pause >nul
goto DISTRO_MENU


:OPEN
cls
echo ================================================================
echo   Open  !sel!  -  choose an account
echo ================================================================
echo.
REM  Load saved accounts for this distro from its accounts file.
REM  Each line is:  username,encrypted-password-blob
set "afile=%~dp0accounts\!sel!.acct"
set acnt=0
if exist "!afile!" (
    for /f "usebackq tokens=1,2 delims=," %%u in ("!afile!") do (
        set /a acnt+=1
        set "auser[!acnt!]=%%u"
        set "ablob[!acnt!]=%%v"
    )
)
echo  Saved accounts:
if !acnt!==0 echo     (none saved yet)
for /l %%i in (1,1,!acnt!) do echo     [%%i] !auser[%%i]!
echo.
echo     [A] Add an account
echo     [W] Open WITHOUT an account
echo     [B] Back
echo.
set "asel="
set /p "asel=Enter your choice: "
if /i "!asel!"=="A" goto ADD_ACCOUNT
if /i "!asel!"=="B" goto DISTRO_MENU
if /i "!asel!"=="W" (
    set "acctuser="
    set "acctblob="
    goto OPEN_METHOD
)
if defined auser[!asel!] (
    for %%c in (!asel!) do (
        set "acctuser=!auser[%%c]!"
        set "acctblob=!ablob[%%c]!"
    )
    goto OPEN_METHOD
)
echo  Invalid choice. Press any key.
pause >nul
goto OPEN


:ADD_ACCOUNT
echo.
set "newuser="
set /p "newuser=Enter the Linux username: "
if "!newuser!"=="" goto OPEN
echo.
echo  Now enter the password (typing is hidden). It will be encrypted.
set "TMPBLOB=%TEMP%\wslblob.txt"
REM  PowerShell reads the password secretly, encrypts it with Windows DPAPI
REM  (tied to your Windows login), and writes only the scrambled hex to a temp file.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=Read-Host 'Password' -AsSecureString; $p=[Net.NetworkCredential]::new('',$s).Password; Add-Type -AssemblyName System.Security; $by=[Text.Encoding]::Unicode.GetBytes($p); $e=[Security.Cryptography.ProtectedData]::Protect($by,$null,'CurrentUser'); Set-Content -NoNewline -Path '%TMPBLOB%' -Value (($e|ForEach-Object{$_.ToString('x2')}) -join '')"
set "blob="
set /p "blob=" < "%TMPBLOB%"
del "%TMPBLOB%" >nul 2>&1
if not exist "%~dp0accounts" mkdir "%~dp0accounts"
>> "!afile!" echo !newuser!,!blob!
echo.
echo  Account "!newuser!" saved for !sel! (password stored encrypted).
pause >nul
goto OPEN


:OPEN_METHOD
cls
echo ================================================================
echo   Open  !sel!
if defined acctuser echo   Account:  !acctuser!
if not defined acctuser echo   Account:  (none - you will type login yourself)
echo ================================================================
echo.
echo     [1] Desktop    visual XFCE window via Remote Desktop
echo     [2] Terminal   command-line window
echo     [B] Back
echo.
set "how="
set /p "how=Enter your choice: "
if "!how!"=="1" goto OPEN_DESKTOP
if "!how!"=="2" goto OPEN_TERMINAL
if /i "!how!"=="B" goto OPEN
echo  Invalid choice. Press any key.
pause >nul
goto OPEN_METHOD


:OPEN_DESKTOP
echo.
REM  Win-KeX distros (Kali) use the "kex" launcher, not xrdp/mstsc. Detect and branch.
echo  Detecting desktop type for !sel! ...
wsl -d !sel! -- bash -lc "command -v kex >/dev/null 2>&1"
if not errorlevel 1 goto OPEN_DESKTOP_KEX
echo  Waking !sel! and starting the desktop server (xrdp)...
wsl -d !sel! -u root -- service xrdp start
echo  Waiting 2 seconds...
timeout /t 2 /nobreak >nul
echo  Checking the desktop server is listening on port 3390...
wsl -d !sel! -u root -- bash -c "ss -lnt | grep 3390"
if errorlevel 1 goto NODESKTOP
set RDP=%TEMP%\wsl-desktop.rdp
> "%RDP%" echo full address:s:localhost:3390
>> "%RDP%" echo screen mode id:i:2
>> "%RDP%" echo dynamic resolution:i:1
>> "%RDP%" echo smart sizing:i:1
>> "%RDP%" echo authentication level:i:0
>> "%RDP%" echo prompt for credentials:i:0
REM  Add the saved username and encrypted password, if an account was chosen.
if defined acctuser (
    >> "%RDP%" echo username:s:!acctuser!
)
if defined acctblob (
    >> "%RDP%" echo password 51:b:!acctblob!
)
REM --- Keep WSL awake while the desktop is in use ---
REM Without this, WSL idle-shuts-down a few seconds after this launcher exits,
REM killing the session (the "opens then closes" problem). This (re)writes a
REM tiny helper and runs it hidden; it self-exits at logout, so RAM frees.
set "KA_B64=IyEvYmluL2Jhc2gKIyBIb2xkIHRoZSBXU0wgVk0gYWxpdmUgd2hpbGUgdGhlIFhGQ0UgZGVza3RvcCBpcyBpbiB1c2UsIHNvIFdTTCdzIGlkbGUKIyBzaHV0ZG93biBkb2VzIG5vdCBraWxsIHRoZSBzZXNzaW9uIHNlY29uZHMgYWZ0ZXIgdGhlIGxhdW5jaGVyIGV4aXRzLgojIFdhaXRzIHVwIHRvIDUgbWluIGZvciB0aGUgZGVza3RvcCB0byBhcHBlYXIsIGhvbGRzIHVudGlsIGl0IGVuZHMsIHRoZW4KIyBleGl0cyBzbyB0aGUgVk0gY2FuIGZyZWUgaXRzZWxmIG5vcm1hbGx5Lgpmb3IgaSBpbiAkKHNlcSAxIDMwMCk7IGRvCiAgICBwZ3JlcCAteCB4ZmNlNC1zZXNzaW9uID4vZGV2L251bGwgMj4mMSAmJiBicmVhawogICAgc2xlZXAgMQpkb25lCndoaWxlIHBncmVwIC14IHhmY2U0LXNlc3Npb24gPi9kZXYvbnVsbCAyPiYxOyBkbwogICAgc2xlZXAgNQpkb25l"
wsl -d !sel! -u root -- bash -c "echo '!KA_B64!' | base64 -d > /usr/local/bin/xrdp-keepalive.sh && chmod +x /usr/local/bin/xrdp-keepalive.sh"
powershell -NoProfile -Command "Start-Process wsl -ArgumentList '-d','!sel!','-u','root','--','/usr/local/bin/xrdp-keepalive.sh' -WindowStyle Hidden"
start "" mstsc "%RDP%"
echo.
echo  Remote Desktop opened.
if not defined acctuser echo  Log in with your Linux username and password.
pause >nul
goto DISTRO_MENU

:NODESKTOP
echo.
echo  This distro has no desktop server the panel knows how to open.
echo  Ubuntu-24.04 opens via xrdp; Kali opens via Win-KeX (kex).
echo  A freshly downloaded distro has neither yet - open it as a
echo  Terminal instead, and install a desktop first.
pause >nul
goto DISTRO_MENU


:OPEN_DESKTOP_KEX
REM  ================================================================
REM  Win-KeX desktop path (Kali). kex MUST run as a NON-ROOT user.
REM  Opens Kali's desktop in its own Win-KeX window - no xrdp, no
REM  mstsc, no port 3390.
REM  ================================================================
REM  Run kex as the saved account if one was chosen, else the distro's
REM  own default user (leave -u off - Kali's default user is non-root).
set "KEXUSER="
if defined acctuser set "KEXUSER=-u !acctuser!"
echo.
echo  Starting the Kali (Win-KeX) desktop for !sel! ...
echo.
echo  A console window titled "Kali Win-KeX" will open:
echo    - FIRST time only: it asks you to set a one-time Win-KeX password
echo      (local only). Type it (twice), then answer "n" to the view-only
echo      question. The desktop opens on its own right after.
echo    - Every time after: it just opens the desktop.
echo  Closing that console does NOT close the desktop.

REM  Keep WSL awake while the desktop is up (same helper/idea as the xrdp
REM  path): Win-KeX runs XFCE, so xfce4-session appears and this holds the VM
REM  so it does not idle-shut-down and kill the desktop seconds after launch.
set "KA_B64=IyEvYmluL2Jhc2gKIyBIb2xkIHRoZSBXU0wgVk0gYWxpdmUgd2hpbGUgdGhlIFhGQ0UgZGVza3RvcCBpcyBpbiB1c2UsIHNvIFdTTCdzIGlkbGUKIyBzaHV0ZG93biBkb2VzIG5vdCBraWxsIHRoZSBzZXNzaW9uIHNlY29uZHMgYWZ0ZXIgdGhlIGxhdW5jaGVyIGV4aXRzLgojIFdhaXRzIHVwIHRvIDUgbWluIGZvciB0aGUgZGVza3RvcCB0byBhcHBlYXIsIGhvbGRzIHVudGlsIGl0IGVuZHMsIHRoZW4KIyBleGl0cyBzbyB0aGUgVk0gY2FuIGZyZWUgaXRzZWxmIG5vcm1hbGx5Lgpmb3IgaSBpbiAkKHNlcSAxIDMwMCk7IGRvCiAgICBwZ3JlcCAteCB4ZmNlNC1zZXNzaW9uID4vZGV2L251bGwgMj4mMSAmJiBicmVhawogICAgc2xlZXAgMQpkb25lCndoaWxlIHBncmVwIC14IHhmY2U0LXNlc3Npb24gPi9kZXYvbnVsbCAyPiYxOyBkbwogICAgc2xlZXAgNQpkb25l"
wsl -d !sel! -u root -- bash -c "echo '!KA_B64!' | base64 -d > /usr/local/bin/xrdp-keepalive.sh && chmod +x /usr/local/bin/xrdp-keepalive.sh"
powershell -NoProfile -Command "Start-Process wsl -ArgumentList '-d','!sel!','-u','root','--','/usr/local/bin/xrdp-keepalive.sh' -WindowStyle Hidden"

REM  Launch Win-KeX in a VISIBLE console from the Linux home. cd ~ avoids the
REM  known "started from a Windows dir" passwd-file failure, and a real console
REM  gives the first-run vncpasswd prompt an interactive terminal - launching it
REM  hidden makes that prompt block forever (that was the "no window" bug).
start "Kali Win-KeX (!sel!)" wsl -d !sel! !KEXUSER! -- bash -lc "cd ~ && unset WAYLAND_DISPLAY && kex --win; echo; read -rp 'Desktop is in its own window. Press Enter to close this console. '"
echo.
echo  Launching Win-KeX - the desktop appears in its own window
echo  (first launch takes a few extra seconds, after you set the password).
echo  If nothing appears, read the "Kali Win-KeX" console for the error.
echo.
pause >nul
goto DISTRO_MENU


:OPEN_TERMINAL
echo.
echo  Opening a terminal window for !sel! ...
if defined acctuser (
    start "!sel!" wsl.exe -d !sel! -u !acctuser!
) else (
    start "!sel!" wsl.exe -d !sel!
)
goto DISTRO_MENU


:DELETE
cls
echo ================================================================
echo   DELETE  !sel!
echo ================================================================
echo.
echo  WARNING: this permanently erases the distro and ALL of its files.
echo  This cannot be undone.
echo.
echo  To confirm, type the distro name EXACTLY:   !sel!
echo  (type anything else to cancel)
echo.
set "confirm="
set /p "confirm=Type name to confirm: "
if "!confirm!"=="!sel!" goto DO_DELETE
echo.
echo  Cancelled - nothing was deleted.
pause >nul
goto MAIN

:DO_DELETE
echo.
echo  Deleting !sel! ...
wsl --unregister !sel!
echo  Done. The folder on D: may remain empty - you can delete it manually.
pause >nul
goto MAIN


:DOWNLOAD
cls
echo ================================================================
echo                    Download a NEW distro
echo ================================================================
echo.
echo  Distros available to install:
echo  ----------------------------------------------------------------
wsl --list --online
echo  ----------------------------------------------------------------
echo.
echo  Type the NAME exactly as shown in the first column (e.g. Debian),
echo  or type B to go back.
echo.
set "newd="
set /p "newd=Distro name: "
if /i "!newd!"=="B" goto MAIN
if "!newd!"=="" goto DOWNLOAD
set "loc=!WSL_BASE!\!newd!"
echo.
echo  Installing !newd! into !loc!
echo  This downloads several hundred MB - please wait...
wsl --install !newd! --location "!loc!" --no-launch
echo.
echo  Finished. To set it up, go back and Open it as a Terminal,
echo  then follow the prompts to create your username and password.
pause >nul
goto MAIN


:UPDATE_WSL
cls
echo ================================================================
echo                 Update / repair WSL itself
echo ================================================================
echo.
echo  This updates the WSL platform to the latest version (fixes many
echo  "won't start" / kernel problems). It needs administrator rights,
echo  so Windows will show a security prompt - click YES.
echo.
echo  Your distros and their files are NOT touched.
echo.
set "go="
set /p "go=Update WSL now? (Y/N): "
if /i not "!go!"=="Y" goto MAIN
echo.
echo  Asking for administrator rights - please click YES on the prompt...
powershell -NoProfile -Command "Start-Process -Verb RunAs -Wait -FilePath 'cmd.exe' -ArgumentList '/c','wsl --update ^& echo. ^& pause'"
echo.
echo  Done. If problems continue, a Windows restart often finishes the job.
echo.
pause >nul
goto MAIN


:SHUTDOWN_ALL
cls
echo ================================================================
echo             Shut down ALL WSL / free memory
echo ================================================================
echo.
echo  This stops EVERY running distro and collapses the WSL virtual
echo  machine (VmmemWSL) via "wsl --shutdown", freeing its memory.
echo.
set "ok="
set /p "ok=Proceed? (Y/N): "
if /i not "!ok!"=="Y" goto MAIN
echo.
echo  Running wsl --shutdown ...
call :STOP_KEX_ALL
wsl --shutdown
echo  Waiting a few seconds for the VM to release...
timeout /t 4 /nobreak >nul
REM  Check the REAL WSL VM process (VmmemWSL), not the unrelated "Vmmem".
set "wslvm=0"
for /f %%v in ('powershell -NoProfile -Command "@(Get-Process VmmemWSL -ErrorAction SilentlyContinue).Count"') do set "wslvm=%%v"
echo.
if "!wslvm!"=="0" (
    echo  Done - WSL VM ^(VmmemWSL^) is closed. Its memory is freed.
) else (
    echo  WSL is shutting down; VmmemWSL is still releasing - it clears
    echo  within a minute, and always fully on a Windows restart.
)
echo.
echo  NOTE: If Task Manager still shows a separate "Vmmem" ^(without the
echo  WSL suffix^), that is NOT Ubuntu - it is another Windows
echo  virtualization feature and is unaffected by wsl --shutdown.
echo.
pause >nul
goto MAIN


:FREEVM
REM  Subroutine: if NO distros are left running, collapse the whole WSL VM
REM  (wsl --shutdown) so the parked Vmmem RAM is freed too, not just the distro.
set rleft=0
for /f "usebackq delims=" %%r in (`wsl --list --running --quiet`) do set /a rleft+=1
if !rleft!==0 (
    echo  No distros left running - freeing the WSL VM memory...
    wsl --shutdown
)
goto :eof


:STOP_KEX
REM  Cleanly stop Win-KeX before terminating a distro, so the Windows-side
REM  VNC viewer window closes too (wsl --terminate alone leaves it hanging).
REM  %~1 = distro name. Safe no-op for distros without kex. Runs as default user.
wsl -d %~1 -- bash -lc "command -v kex >/dev/null 2>&1"
if errorlevel 1 goto :eof
echo  Stopping Win-KeX on %~1 ...
wsl -d %~1 -- bash -lc "cd ~ && kex --stop >/dev/null 2>&1"
goto :eof


:STOP_KEX_ALL
REM  Stop Win-KeX on every currently-running distro (before a full wsl --shutdown).
for /f "usebackq delims=" %%r in (`wsl --list --running --quiet`) do call :STOP_KEX "%%r"
goto :eof


:END
endlocal
exit /b
