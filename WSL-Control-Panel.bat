:: ================================================================
::  WSL / Ubuntu Control Panel
::  List, open (with saved accounts), close, delete, download distros.
::  Passwords are stored ENCRYPTED with Windows DPAPI, never plain text.
::  Lines starting with REM or :: are comments .
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
REM  Is a working, modern WSL present?  The real WSL platform always installs
REM  its files to "C:\Program Files\WSL", so we check for that file FIRST - it
REM  is instant. We must NOT run wsl.exe before that: on a PC where WSL was
REM  never set up, Windows' built-in wsl.exe does not fail - it waits at a
REM  hidden "Press any key to install WSL" prompt for 60 seconds, and because
REM  its output goes to nul, the panel sat on a blank black window.
REM  Once the files exist, "wsl --version" is a quick health check (exits 0
REM  when WSL really works). Either failure opens the guided one-time setup.
if not exist "%ProgramFiles%\WSL\wsl.exe" goto SETUP_WSL
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
REM  Same instant file check as CHECK_WSL (never run wsl.exe while WSL is
REM  missing - it would sit on its hidden 60-second prompt). Turning on WSL's
REM  Windows features for the first time needs a restart; Windows flags that
REM  with the registry key "Component Based Servicing\RebootPending". While it
REM  exists, distros cannot run yet, so we say RESTART instead of "ready".
set "wslstate=READY"
if not exist "%ProgramFiles%\WSL\wsl.exe" set "wslstate=MISSING"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1 && set "wslstate=RESTART"
if "!wslstate!"=="READY" (
    wsl --version >nul 2>&1 || set "wslstate=RESTART"
)
if "!wslstate!"=="READY" (
    echo.
    echo  WSL is installed and ready. Continuing to the control panel,
    echo  where you can download a Linux distro with the [N] option.
    echo.
    pause >nul
    goto MAIN
)
if "!wslstate!"=="MISSING" (
    echo.
    echo  WSL did not get installed. This happens if you clicked NO on the
    echo  Windows security prompt, or the administrator window showed an
    echo  error, for example no internet. Run this panel again to retry.
    echo.
    pause >nul
    goto END
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
REM  Collect the distro names, one per line. With NO distros (a fresh PC) WSL
REM  prints a message instead ("...has no installed distributions..."), so we
REM  hide its error output and skip any line containing a space - a real
REM  distro name never has one.
for /f "usebackq tokens=1* delims= " %%d in (`wsl --list --quiet 2^>nul`) do if "%%e"=="" (
    set /a count+=1
    set "distro[!count!]=%%d"
)
echo  Just press ENTER to quick-open your desktop (wakes it first), or:
echo.
echo  Pick a distro by NUMBER to manage it (open / close / delete):
if !count!==0 echo     (none yet - use [N] below to download your first distro)
for /l %%i in (1,1,!count!) do echo     [%%i] !distro[%%i]!
echo.
echo     [C] Close a running distro   - stops one distro, frees its RAM
echo     [S] Shut down ALL WSL         - stops everything, frees the WSL VM
echo     [N] Download a NEW distro     - runs "wsl --install" for a fresh Linux
echo     [U] Update / repair WSL       - runs "wsl --update" (admin) to fix WSL
echo     [Q] Quit                      - close this panel (distros keep running)
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
echo  Closing a distro runs "wsl --terminate" to stop it and free its RAM.
echo  Your files are kept - it just powers the Linux machine off.
echo.
echo  Currently running:
for /l %%i in (1,1,!rcount!) do echo     [%%i] !run[%%i]!
echo.
echo     [A] Close ALL running distros - stops every one at once
echo     [B] Back                      - return to the main menu
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
echo     [O] Open this distro     - pick an account, then Desktop or Terminal
if "!state!"=="RUNNING" echo     [C] Close this distro     - "wsl --terminate", frees its RAM
echo     [D] Delete this distro   - "wsl --unregister" - ERASES it (permanent!)
echo     [B] Back to the list     - return to the main menu
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
echo  A "saved account" stores a Linux username + encrypted password so the
echo  panel can log you in automatically. Pick one by number, or:
echo.
echo  Saved accounts:
if !acnt!==0 echo     (none saved yet)
for /l %%i in (1,1,!acnt!) do echo     [%%i] !auser[%%i]!
echo.
echo     [A] Add an account          - save a login, and (for a fresh distro)
echo                                   CREATE the Linux user so login works
echo     [W] Open WITHOUT an account - just open; you type your login yourself
echo     [B] Back                    - return to the distro menu
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
REM  ================================================================
REM  Two separate things happen here, and this is the bit that trips
REM  new users up:
REM    1. The panel always SAVES the username + an encrypted password
REM       so Remote Desktop / the terminal can auto-fill your login.
REM    2. Optionally, it also CREATES that user INSIDE the distro (so
REM       the login actually exists). A freshly downloaded distro has
REM       only "root", so without this step the desktop login fails
REM       with "user does not exist, or could not be authenticated".
REM  ================================================================
echo  Do you also want to CREATE this user inside !sel! now?
echo    [Y] Yes - new / fresh distro with no login yet. Makes the Linux
echo        user, gives it sudo (admin), and sets up the XFCE desktop
echo        session. Use this if desktop login said "user does not exist".
echo    [N] No  - the Linux user already exists; only remember it here
echo        for auto-login (does not touch the distro).
echo.
set "MKUSER=0"
set "mk="
set /p "mk=Create the Linux user too? (Y/N) [Y]: "
if not defined mk set "MKUSER=1"
if /i "!mk!"=="Y" set "MKUSER=1"
echo.
if "!MKUSER!"=="1" (
    echo  Enter a password for "!newuser!" - you will type it twice.
    echo  This becomes the Linux login password AND is saved here encrypted.
) else (
    echo  Enter the existing Linux password for "!newuser!" - typed twice.
    echo  It is only saved here encrypted; the distro is not changed.
)
set "TMPBLOB=%TEMP%\wslblob.txt"
REM  PowerShell reads the password secretly (twice, to catch typos) and encrypts
REM  it with Windows DPAPI (tied to your Windows login), writing only the scrambled
REM  hex to a temp file. If MKUSER=1 it ALSO creates the Linux user in the distro:
REM  useradd + add to whichever admin group exists (sudo on Debian family, wheel
REM  on Fedora/openSUSE/Arch) + an XFCE .xsession, then pipes user:password
REM  straight into "chpasswd" over stdin - the password never lands on disk or on a
REM  command line. Exit 3 = the two passwords differed; exit 4 = the distro refused
REM  the user/password (e.g. distro not healthy). Only single quotes are used inside
REM  -Command so every "|" stays literal to cmd.exe.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=Read-Host 'Password' -AsSecureString; $s2=Read-Host 'Confirm password' -AsSecureString; $p=[Net.NetworkCredential]::new('',$s).Password; $p2=[Net.NetworkCredential]::new('',$s2).Password; if($p -ne $p2){ Write-Host 'Passwords did not match.'; exit 3 }; Add-Type -AssemblyName System.Security; $by=[Text.Encoding]::Unicode.GetBytes($p); $e=[Security.Cryptography.ProtectedData]::Protect($by,$null,'CurrentUser'); Set-Content -NoNewline -Path '%TMPBLOB%' -Value (($e|ForEach-Object{$_.ToString('x2')}) -join ''); if('!MKUSER!' -eq '1'){ $u='!newuser!'; $script='v=$1; id -u $v >/dev/null 2>&1 || useradd -m -s /bin/bash $v; if getent group sudo >/dev/null 2>&1; then usermod -aG sudo $v; elif getent group wheel >/dev/null 2>&1; then usermod -aG wheel $v; fi; H=$(getent passwd $v | cut -d: -f6); H=${H:-/home/$v}; echo startxfce4 > $H/.xsession; chown ${v}:${v} $H/.xsession 2>/dev/null'; wsl -d !sel! -u root -- bash -c $script _ $u; ($u + ':' + $p) | wsl -d !sel! -u root -- chpasswd; if($LASTEXITCODE -ne 0){ Write-Host 'Could not set the user/password in the distro.'; exit 4 } }"
if errorlevel 4 (
    del "%TMPBLOB%" >nul 2>&1
    echo.
    echo  The Linux user/password could not be set inside !sel!. Nothing saved.
    echo  Open the distro as a Terminal and check it is healthy, then try again.
    pause >nul
    goto OPEN
)
if errorlevel 3 (
    del "%TMPBLOB%" >nul 2>&1
    echo.
    echo  The two passwords did not match - nothing saved. Please try again.
    pause >nul
    goto OPEN
)
set "blob="
set /p "blob=" < "%TMPBLOB%"
del "%TMPBLOB%" >nul 2>&1
if not defined blob (
    echo.
    echo  Could not read the encrypted password - nothing saved. Try again.
    pause >nul
    goto OPEN
)
if not exist "%~dp0accounts" mkdir "%~dp0accounts"
REM  Drop any previous saved line for this same username so entries don't pile
REM  up (e.g. a stale one from before the Linux user existed). Single quotes only
REM  inside -Command so the "|" pipes stay literal to cmd.exe.
if exist "!afile!" powershell -NoProfile -Command "$f='!afile!'; $u='!newuser!'; (Get-Content -LiteralPath $f) | Where-Object { $_ -notlike ($u + ',*') } | Set-Content -LiteralPath $f"
>> "!afile!" echo !newuser!,!blob!
echo.
if "!MKUSER!"=="1" (
    echo  Done. User "!newuser!" was CREATED inside !sel! with sudo rights and an
    echo  XFCE desktop session, and saved here for auto-login. You can now Open
    echo  this distro as Desktop or Terminal using this account.
) else (
    echo  Account "!newuser!" saved for !sel! - password stored encrypted.
    echo  NOTE: this did NOT create the Linux user - it only remembers the login.
)
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
echo     [1] Desktop    - full graphical XFCE desktop.
echo                      Kali opens in a Win-KeX window; other distros open in
echo                      Windows Remote Desktop (mstsc) via an xrdp server.
echo     [2] Terminal   - a command-line window (fastest; no desktop needed).
echo     [B] Back       - return to the account list.
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
REM  Start xrdp across any distro: SysV "service" (Debian/Ubuntu/Kali), else
REM  systemd "systemctl" (Fedora/openSUSE with systemd on), else launch the
REM  xrdp-sesman + xrdp binaries directly (WSL often has no init running).
wsl -d !sel! -u root -- bash -c "if service xrdp start >/dev/null 2>&1; then :; elif systemctl start xrdp >/dev/null 2>&1; then systemctl start xrdp-sesman >/dev/null 2>&1; else pgrep -x xrdp-sesman >/dev/null 2>&1 || (/usr/sbin/xrdp-sesman >/dev/null 2>&1 &); sleep 1; pgrep -x xrdp >/dev/null 2>&1 || (/usr/sbin/xrdp >/dev/null 2>&1 &); fi"
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
echo  A freshly downloaded distro has neither yet.
echo.
echo  I can download and install one for you now:
echo    - Kali:      kali-win-kex (its own Win-KeX desktop)
echo    - Any other: XFCE desktop + xrdp on port 3390. The installer
echo                 auto-detects the package manager (apt / dnf / zypper
echo                 / yum / pacman), so it is not limited to Ubuntu/Debian.
echo  This needs internet and a few hundred MB; it can take several minutes.
echo.
echo    [I] Install the desktop now (auto)
echo    [T] Open as a Terminal instead
echo    [B] Back
echo.
set "ndchoice="
set /p "ndchoice=Enter your choice: "
if /i "!ndchoice!"=="T" goto OPEN_TERMINAL
if /i "!ndchoice!"=="I" goto INSTALL_DESKTOP
goto DISTRO_MENU


:INSTALL_DESKTOP
REM  ================================================================
REM  Download + install a desktop for a distro that has none yet.
REM    - Kali             -> kali-win-kex (its own first-party Win-KeX GUI).
REM    - Any other distro -> XFCE + xrdp. The installer script AUTO-DETECTS
REM      the package manager (apt / dnf / zypper / yum / pacman), installs
REM      the matching packages, puts xrdp on port 3390, makes XFCE the
REM      default session, and starts xrdp. That script is carried in as
REM      base64 (DESK_B64) so no layer of shell quoting can mangle it.
REM  Runs as root. On success we loop back to OPEN_DESKTOP to retry.
REM  ================================================================
REM  Kali is the one distro we branch by NAME: it needs kex, but kex is not
REM  installed yet, so we cannot detect it by capability the way OPEN does.
echo !sel! | findstr /i "kali" >nul
if not errorlevel 1 goto INSTALL_DESKTOP_KEX

echo.
echo  Installing an XFCE desktop + xrdp on !sel! ...
echo  (auto-detecting the package manager - this can take several minutes)
echo.
set "DESK_B64=IyEvYmluL2Jhc2gKIyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CiMgQXV0by1pbnN0YWxsIGFuIFhGQ0UgZGVza3RvcCArIHhyZHAgb24gQU5ZIGNvbW1vbiBXU0wgZGlzdHJvLCB0aGVuIHB1dCB4cmRwCiMgb24gcG9ydCAzMzkwIGFuZCBtYWtlIFhGQ0UgdGhlIGRlZmF1bHQgUkRQIHNlc3Npb24uIERlY29kZWQgZnJvbSBiYXNlNjQgYW5kCiMgcnVuIGJ5IHRoZSBXU0wgQ29udHJvbCBQYW5lbC4gUHJpbnRzIERFU0tfU0VUVVBfRE9ORSBvbiBzdWNjZXNzOyBhIG5vbi16ZXJvCiMgZXhpdCB0ZWxscyB0aGUgcGFuZWwgdGhlIGluc3RhbGwgZmFpbGVkLgojID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KCmluc3RhbGxfYXB0KCkgewogICAgZXhwb3J0IERFQklBTl9GUk9OVEVORD1ub25pbnRlcmFjdGl2ZQogICAgYXB0LWdldCB1cGRhdGUKICAgIGFwdC1nZXQgaW5zdGFsbCAteSB4ZmNlNCB4ZmNlNC1nb29kaWVzIHhyZHAgZGJ1cy14MTEKfQppbnN0YWxsX2RuZigpIHsKICAgIGRuZiBpbnN0YWxsIC15IHhyZHAgeG9yZ3hyZHAKICAgIGRuZiBncm91cCBpbnN0YWxsIC15ICJYZmNlIERlc2t0b3AiIFwKICAgICAgfHwgZG5mIGdyb3VwaW5zdGFsbCAteSAiWGZjZSIgXAogICAgICB8fCBkbmYgaW5zdGFsbCAteSBAeGZjZS1kZXNrdG9wLWVudmlyb25tZW50Cn0KaW5zdGFsbF95dW0oKSB7CiAgICB5dW0gaW5zdGFsbCAteSBlcGVsLXJlbGVhc2UgfHwgdHJ1ZQogICAgeXVtIGdyb3VwaW5zdGFsbCAteSAiWGZjZSIgfHwgdHJ1ZQogICAgeXVtIGluc3RhbGwgLXkgeHJkcAp9Cmluc3RhbGxfenlwcGVyKCkgewogICAgenlwcGVyIC0tbm9uLWludGVyYWN0aXZlIGluc3RhbGwgeHJkcAogICAgenlwcGVyIC0tbm9uLWludGVyYWN0aXZlIGluc3RhbGwgLXQgcGF0dGVybiB4ZmNlCn0KaW5zdGFsbF9wYWNtYW4oKSB7CiAgICBwYWNtYW4gLVN5IC0tbm9jb25maXJtIHhmY2U0CiAgICAjIHhyZHAgaXMgbm90IGluIEFyY2gncyBvZmZpY2lhbCByZXBvcyAoaXQgbGl2ZXMgaW4gdGhlIEFVUiksIHNvIHRoaXMgbWF5CiAgICAjIGZhaWwgLSByZXBvcnQgY2xlYXJseSByYXRoZXIgdGhhbiBsZWF2aW5nIGEgaGFsZi1jb25maWd1cmVkIGRlc2t0b3AuCiAgICBwYWNtYW4gLVMgLS1ub2NvbmZpcm0geHJkcCB8fCB7CiAgICAgICAgZWNobyAiWFJEUF9OT1RfSU5fUkVQTyIKICAgICAgICBleGl0IDIwCiAgICB9Cn0KCiMgLS0tIFBpY2sgdGhlIHBhY2thZ2UgbWFuYWdlciBhbmQgaW5zdGFsbCAodGhpcyBwYXJ0IG11c3Qgc3VjY2VlZCkgLS0tCnNldCAtZQppZiBjb21tYW5kIC12IGFwdC1nZXQgPi9kZXYvbnVsbCAyPiYxOyAgIHRoZW4gUE09YXB0OyAgICBlY2hvICJQYWNrYWdlIG1hbmFnZXI6IGFwdCI7ICAgIGluc3RhbGxfYXB0CmVsaWYgY29tbWFuZCAtdiBkbmYgICA+L2Rldi9udWxsIDI+JjE7ICAgdGhlbiBQTT1kbmY7ICAgIGVjaG8gIlBhY2thZ2UgbWFuYWdlcjogZG5mIjsgICAgaW5zdGFsbF9kbmYKZWxpZiBjb21tYW5kIC12IHp5cHBlciA+L2Rldi9udWxsIDI+JjE7ICB0aGVuIFBNPXp5cHBlcjsgZWNobyAiUGFja2FnZSBtYW5hZ2VyOiB6eXBwZXIiOyBpbnN0YWxsX3p5cHBlcgplbGlmIGNvbW1hbmQgLXYgeXVtICAgPi9kZXYvbnVsbCAyPiYxOyAgIHRoZW4gUE09eXVtOyAgICBlY2hvICJQYWNrYWdlIG1hbmFnZXI6IHl1bSI7ICAgIGluc3RhbGxfeXVtCmVsaWYgY29tbWFuZCAtdiBwYWNtYW4gPi9kZXYvbnVsbCAyPiYxOyAgdGhlbiBQTT1wYWNtYW47IGVjaG8gIlBhY2thZ2UgbWFuYWdlcjogcGFjbWFuIjsgaW5zdGFsbF9wYWNtYW4KZWxzZQogICAgZWNobyAiVU5LTk9XTl9QS0dfTUFOQUdFUiIKICAgIGV4aXQgMjEKZmkKc2V0ICtlCgojIC0tLSBFdmVyeXRoaW5nIGJlbG93IGlzIGJlc3QtZWZmb3J0IGNvbmZpZ3VyYXRpb24gKG5ldmVyIGZhaWxzIHRoZSBpbnN0YWxsKSAtLS0KCiMgUG9pbnQgeHJkcCBhdCBwb3J0IDMzOTAgKHRoZSBwb3J0IHRoZSBwYW5lbCdzIFJlbW90ZSBEZXNrdG9wIGNvbm5lY3RzIHRvKS4KaWYgWyAtZiAvZXRjL3hyZHAveHJkcC5pbmkgXTsgdGhlbgogICAgc2VkIC1pICdzL15wb3J0PTMzODkvcG9ydD0zMzkwLycgL2V0Yy94cmRwL3hyZHAuaW5pCiAgICBncmVwIC1xICdecG9ydD0zMzkwJyAvZXRjL3hyZHAveHJkcC5pbmkgXAogICAgICB8fCBzZWQgLWkgJzAsL15cW0dsb2JhbHNcXS9zLy9bR2xvYmFsc11cbnBvcnQ9MzM5MC8nIC9ldGMveHJkcC94cmRwLmluaQpmaQoKIyBNYWtlIFhGQ0UgdGhlIGRlZmF1bHQgc2Vzc2lvbiBmb3IgY3VycmVudCBhbmQgZnV0dXJlIHVzZXJzLgpta2RpciAtcCAvZXRjL3NrZWwKZWNobyBzdGFydHhmY2U0ID4gL2V0Yy9za2VsLy54c2Vzc2lvbgpmb3IgaCBpbiAvcm9vdCAvaG9tZS8qOyBkbwogICAgWyAtZCAiJGgiIF0gfHwgY29udGludWUKICAgIGVjaG8gc3RhcnR4ZmNlNCA+ICIkaC8ueHNlc3Npb24iCiAgICBjaG93biAtLXJlZmVyZW5jZT0iJGgiICIkaC8ueHNlc3Npb24iIDI+L2Rldi9udWxsIHx8IHRydWUKZG9uZQoKIyBEZWJpYW4gd2FudHMgdGhlIHhyZHAgdXNlciBpbiBzc2wtY2VydDsgaGFybWxlc3MgaWYgYWJzZW50IGVsc2V3aGVyZS4KZ2V0ZW50IGdyb3VwIHNzbC1jZXJ0ID4vZGV2L251bGwgMj4mMSAmJiB1c2VybW9kIC1hRyBzc2wtY2VydCB4cmRwIDI+L2Rldi9udWxsIHx8IHRydWUKCiMgU3RhcnQgeHJkcCBub3c6IFN5c1Ygc2VydmljZSwgZWxzZSBzeXN0ZW1kLCBlbHNlIHRoZSBiaW5hcmllcyBkaXJlY3RseQojIChXU0wgZGlzdHJvcyBvZnRlbiBydW4gd2l0aG91dCBzeXN0ZW1kLCBzbyBmYWxsIGFsbCB0aGUgd2F5IHRocm91Z2gpLgppZiBzZXJ2aWNlIHhyZHAgc3RhcnQgPi9kZXYvbnVsbCAyPiYxOyB0aGVuCiAgICA6CmVsaWYgc3lzdGVtY3RsIHN0YXJ0IHhyZHAgPi9kZXYvbnVsbCAyPiYxOyB0aGVuCiAgICBzeXN0ZW1jdGwgc3RhcnQgeHJkcC1zZXNtYW4gPi9kZXYvbnVsbCAyPiYxCmVsc2UKICAgIHBncmVwIC14IHhyZHAtc2VzbWFuID4vZGV2L251bGwgMj4mMSB8fCAoL3Vzci9zYmluL3hyZHAtc2VzbWFuID4vZGV2L251bGwgMj4mMSAmKQogICAgc2xlZXAgMQogICAgcGdyZXAgLXggeHJkcCA+L2Rldi9udWxsIDI+JjEgfHwgKC91c3Ivc2Jpbi94cmRwID4vZGV2L251bGwgMj4mMSAmKQpmaQoKZWNobyBERVNLX1NFVFVQX0RPTkUKZXhpdCAwCg=="
wsl -d !sel! -u root -- bash -c "echo '!DESK_B64!' | base64 -d | bash"
if errorlevel 1 goto INSTALL_DESKTOP_FAIL
echo.
echo  Done. XFCE + xrdp installed and set to port 3390.
echo  Opening the desktop now...
timeout /t 2 /nobreak >nul
goto OPEN_DESKTOP

:INSTALL_DESKTOP_KEX
echo.
echo  Installing kali-win-kex on !sel! (this can take several minutes)...
echo.
wsl -d !sel! -u root -- bash -lc "set -e; export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y kali-win-kex"
if errorlevel 1 goto INSTALL_DESKTOP_FAIL
echo.
echo  Done. Win-KeX installed.
echo  Opening the desktop now...
timeout /t 2 /nobreak >nul
goto OPEN_DESKTOP

:INSTALL_DESKTOP_FAIL
echo.
echo  The desktop install did not complete. Common causes:
echo    - no internet connection inside the distro
echo    - the package manager is locked by another update running now
echo    - out of disk space
echo    - Arch: xrdp is not in the official repos (it is in the AUR), so it
echo      cannot be auto-installed - it prints XRDP_NOT_IN_REPO above
echo    - an unrecognised package manager (not apt/dnf/zypper/yum/pacman) -
echo      it prints UNKNOWN_PKG_MANAGER above
echo  Open the distro as a Terminal to read the output above, then try again.
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
echo.
echo  Where should !newd! be installed?
echo    - Press ENTER to use the default base folder:  !WSL_BASE!
echo    - Or type a different folder, e.g. C:\WSL or E:\Linux
echo.
set "base=!WSL_BASE!"
set /p "base=Install folder [!WSL_BASE!]: "
if not defined base set "base=!WSL_BASE!"
set "loc=!base!\!newd!"
if not exist "!base!" mkdir "!base!" 2>nul
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
