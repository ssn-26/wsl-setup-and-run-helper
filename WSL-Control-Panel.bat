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
REM  Where [E] Back up saves distro backups (.tar files) and where [R] Restore
REM  looks for them. Copy this folder to a USB drive / cloud to move your
REM  distros to another PC.
set "BACKUP_BASE=D:\Linux\Backups"
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
echo     [E] Back up a distro          - "wsl --export" saves it all to one file
echo     [R] Restore a backup          - "wsl --import" brings a backup back
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
if /i "!choice!"=="E" goto BACKUP
if /i "!choice!"=="R" goto RESTORE
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
    wsl --terminate !target! <nul
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
wsl --terminate !sel! <nul
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
REM  hex to a temp file. If MKUSER=1 it ALSO creates the Linux user in the distro
REM  by running a small script carried as base64 (USER_B64): useradd + add to
REM  whichever admin group exists (sudo on Debian family, wheel on Fedora/
REM  openSUSE/Arch - installing sudo and its wheel rule if missing, as on Arch)
REM  + XFCE .xsession/.xinitrc. Then it pipes user:password straight into
REM  "chpasswd" over stdin - the password never lands on disk or on a command
REM  line. "wsl -e" (exec) is used so no extra Linux shell re-reads the command:
REM  with "wsl --", that shell expanded $1 too early and the user was never made.
REM  sed strips the invisible byte-order mark and trailing \r that PowerShell adds
REM  when piping text - left in, they corrupt the username and the password.
REM  Exit 3 = the two passwords differed; exit 4 = the distro refused the
REM  user/password (e.g. distro not healthy). Only single quotes are used inside
REM  -Command so every "|" stays literal to cmd.exe.
set "USER_B64=IyEvYmluL2Jhc2gKIyBDcmVhdGUgKG9yIHVwZGF0ZSkgYSBMaW51eCBsb2dpbiB1c2VyIHdpdGggYWRtaW4gcmlnaHRzIGFuZCBhbiBYRkNFIGRlc2t0b3AKIyBzZXNzaW9uLiBEZWNvZGVkIGZyb20gYmFzZTY0IGFuZCBydW4gYXMgcm9vdCBieSB0aGUgV1NMIENvbnRyb2wgUGFuZWwncwojICJBZGQgYWNjb3VudCI7ICQxID0gdXNlcm5hbWUuIFRoZSBwYXNzd29yZCBpcyBzZXQgc2VwYXJhdGVseSAoY2hwYXNzd2QpLgp2PSQxCmlkIC11ICIkdiIgPi9kZXYvbnVsbCAyPiYxIHx8IHVzZXJhZGQgLW0gLXMgL2Jpbi9iYXNoICIkdiIKaWYgZ2V0ZW50IGdyb3VwIHN1ZG8gPi9kZXYvbnVsbCAyPiYxOyB0aGVuCiAgICB1c2VybW9kIC1hRyBzdWRvICIkdiIKZWxpZiBnZXRlbnQgZ3JvdXAgd2hlZWwgPi9kZXYvbnVsbCAyPiYxOyB0aGVuCiAgICB1c2VybW9kIC1hRyB3aGVlbCAiJHYiCiAgICAjIEFyY2ggc2hpcHMgd2l0aG91dCBzdWRvLCBhbmQgb24gbW9zdCB3aGVlbCBkaXN0cm9zIHRoZSBydWxlIHRoYXQgbGV0cwogICAgIyB3aGVlbCB1c2Ugc3VkbyBjYW4gYmUgbWlzc2luZyAtIGluc3RhbGwgc3VkbyBhbmQgYWRkIHRoZSBydWxlIGlmIG5lZWRlZC4KICAgIGlmICEgY29tbWFuZCAtdiBzdWRvID4vZGV2L251bGwgMj4mMSAmJiBjb21tYW5kIC12IHBhY21hbiA+L2Rldi9udWxsIDI+JjE7IHRoZW4KICAgICAgICAjIEJyYW5kLW5ldyBBcmNoIGhhcyBubyBwYWNtYW4gc2lnbmluZyBrZXlzIHVudGlsIGl0cyBmaXJzdC1ydW4gc2NyaXB0CiAgICAgICAgIyBydW5zIC0gc2V0IHRoZW0gdXAsIG9yIHRoZSBkb3dubG9hZCBiZWxvdyBmYWlscy4KICAgICAgICBpZiAhIHBhY21hbi1rZXkgLS1saXN0LWtleXMgMj4vZGV2L251bGwgfCBncmVwIC1xICdecHViJzsgdGhlbgogICAgICAgICAgICBwYWNtYW4ta2V5IC0taW5pdCA+L2Rldi9udWxsIDI+JjEKICAgICAgICAgICAgcGFjbWFuLWtleSAtLXBvcHVsYXRlIGFyY2hsaW51eCA+L2Rldi9udWxsIDI+JjEKICAgICAgICBmaQogICAgICAgIHBhY21hbiAtU3l1IC0tbmVlZGVkIC0tbm9jb25maXJtIHN1ZG8gPi9kZXYvbnVsbAogICAgZmkKICAgIGlmICEgZ3JlcCAtRXFzICdeW1s6c3BhY2U6XV0qJXdoZWVsW1s6c3BhY2U6XV0nIC9ldGMvc3Vkb2VycyAvZXRjL3N1ZG9lcnMuZC8qOyB0aGVuCiAgICAgICAgbWtkaXIgLXAgL2V0Yy9zdWRvZXJzLmQKICAgICAgICBlY2hvICcld2hlZWwgQUxMPShBTEw6QUxMKSBBTEwnID4gL2V0Yy9zdWRvZXJzLmQvMTAtd2hlZWwKICAgICAgICBjaG1vZCA0NDAgL2V0Yy9zdWRvZXJzLmQvMTAtd2hlZWwKICAgIGZpCmZpCkg9JChnZXRlbnQgcGFzc3dkICIkdiIgfCBjdXQgLWQ6IC1mNik7IEg9JHtIOi0vaG9tZS8kdn0KZm9yIGYgaW4gLnhzZXNzaW9uIC54aW5pdHJjOyBkbwogICAgZWNobyAnZXhlYyBzdGFydHhmY2U0JyA+ICIkSC8kZiIKICAgIGNob3duICIkdjokdiIgIiRILyRmIiAyPi9kZXYvbnVsbApkb25lCmV4aXQgMAo="
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=Read-Host 'Password' -AsSecureString; $s2=Read-Host 'Confirm password' -AsSecureString; $p=[Net.NetworkCredential]::new('',$s).Password; $p2=[Net.NetworkCredential]::new('',$s2).Password; if($p -ne $p2){ Write-Host 'Passwords did not match.'; exit 3 }; Add-Type -AssemblyName System.Security; $by=[Text.Encoding]::Unicode.GetBytes($p); $e=[Security.Cryptography.ProtectedData]::Protect($by,$null,'CurrentUser'); Set-Content -NoNewline -Path '%TMPBLOB%' -Value (($e|ForEach-Object{$_.ToString('x2')}) -join ''); if('!MKUSER!' -eq '1'){ $u='!newuser!'; $b='!USER_B64!'; wsl -d !sel! -u root -e bash -c ('echo ' + $b + ' | base64 -d | bash -s -- $0') $u; ($u + ':' + $p) | wsl -d !sel! -u root -e bash -c 'sed -e ''s/\xef\xbb\xbf//'' -e ''s/\r$//'' | chpasswd'; if($LASTEXITCODE -ne 0){ Write-Host 'Could not set the user/password in the distro.'; exit 4 } }"
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
wsl -d !sel! -- bash -lc "command -v kex >/dev/null 2>&1" <nul
if not errorlevel 1 goto OPEN_DESKTOP_KEX
REM  All WSL2 distros share ONE network, so only one of them can hold port
REM  3390 at a time. If ANOTHER running distro's xrdp already has it, this
REM  distro's xrdp cannot start there - and Remote Desktop would open THAT
REM  other distro's desktop instead. Find it and offer to close it.
set "p3390="
for /f "usebackq delims=" %%r in (`wsl --list --running --quiet`) do if /i not "%%r"=="!sel!" (
    wsl -d %%r -u root -e sh -c "ss -lntp 2>/dev/null | grep ':3390 ' | grep -q xrdp" <nul >nul 2>&1 && set "p3390=%%r"
)
if defined p3390 (
    echo.
    echo  !p3390! is running its own desktop on port 3390. WSL distros share one
    echo  network, so only one xrdp desktop can use that port at a time.
    echo    [Y] Close !p3390! now ^(its desktop session ends - save work first^)
    echo    [N] Cancel
    set "pc="
    set /p "pc=Close !p3390! and continue? (Y/N): "
    if /i not "!pc!"=="Y" goto DISTRO_MENU
    wsl --terminate !p3390! <nul >nul 2>&1
    echo  !p3390! closed.
)
echo  Waking !sel! and starting the desktop server (xrdp)...
REM  Start xrdp across any distro: SysV "service" (Debian/Ubuntu/Kali), else
REM  systemd "systemctl" (Fedora/openSUSE with systemd on), else launch the
REM  xrdp-sesman + xrdp binaries directly (WSL often has no init running).
wsl -d !sel! -u root -- bash -c "if service xrdp start >/dev/null 2>&1; then :; elif systemctl start xrdp >/dev/null 2>&1; then systemctl start xrdp-sesman >/dev/null 2>&1; else pgrep -x xrdp-sesman >/dev/null 2>&1 || (/usr/sbin/xrdp-sesman >/dev/null 2>&1 &); sleep 1; pgrep -x xrdp >/dev/null 2>&1 || (/usr/sbin/xrdp >/dev/null 2>&1 &); fi" <nul
echo  Waiting 2 seconds...
timeout /t 2 /nobreak >nul
echo  Checking the desktop server is listening on port 3390...
REM  "-p" shows the owning program, and only for THIS distro's own processes,
REM  so a listener belonging to another distro does not count as ours.
wsl -d !sel! -u root -e sh -c "ss -lntp 2>/dev/null | grep ':3390 ' | grep -q xrdp" <nul
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
wsl -d !sel! -u root -- bash -c "echo '!KA_B64!' | base64 -d > /usr/local/bin/xrdp-keepalive.sh && chmod +x /usr/local/bin/xrdp-keepalive.sh" <nul
powershell -NoProfile -Command "Start-Process wsl -ArgumentList '-d','!sel!','-u','root','--','/usr/local/bin/xrdp-keepalive.sh' -WindowStyle Hidden" <nul
start "" mstsc "%RDP%"
echo.
echo  Remote Desktop opened.
if not defined acctuser echo  Log in with your Linux username and password.
pause >nul
goto DISTRO_MENU

:NODESKTOP
echo.
echo  This distro has no desktop server the panel knows how to open.
echo  Most distros open via xrdp; Kali opens via Win-KeX (kex).
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
REM      base64 (the echo lines below) so no layer of shell quoting can mangle it.
REM    - Arch: xrdp/xorgxrdp are not in the official repos, so the script
REM      builds them from the AUR with a temporary non-root "aurbuild" user
REM      (removed afterwards). It also sets up pacman's signing keys, which
REM      a brand-new Arch lacks until its first-run script runs.
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
REM  The installer is written to a temp file in short lines and streamed into
REM  the distro. A single cmd line may not exceed 8191 characters, and the
REM  whole installer as one line is longer than that - cmd silently dropped
REM  the command. tr strips the Windows line endings echo adds before decoding;
REM  the script then runs with stdin from /dev/null so no installer step can
REM  read (and eat) the rest of it.
set "DESKTMP=%TEMP%\wsl-desktop-setup.b64"
> "%DESKTMP%" echo IyEvYmluL2Jhc2gKIyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CiMgQXV0by1pbnN0YWxsIGFuIFhGQ0UgZGVza3RvcCArIHhyZHAgb24gQU5ZIGNvbW1vbiBXU0wgZGlzdHJvLCB0aGVuIHB1dCB4cmRwCiMgb24gcG9ydCAzMzkwIGFuZCBtYWtlIFhGQ0UgdGhlIGRlZmF1bHQgUkRQIHNlc3Npb24uIERlY29kZWQgZnJvbSBiYXNlNjQgYW5kCiMgcnVuIGJ5IHRoZSBXU0wgQ29udHJvbCBQYW5lbC4gUHJpbnRzIERFU0tfU0VUVVBfRE9ORSBvbiBzdWNjZXNzOyBhIG5vbi16ZXJvCiMgZXhpdCB0ZWxscyB0aGUgcGFuZWwgdGhlIGluc3RhbGwgZmFpbGVkLgojID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KCmluc3RhbGxfYXB0KCkgewogICAgZXhwb3J0IERFQklBTl9GUk9OVEVORD1ub25pbnRlcmFjdGl2ZQogICAgYXB0LWdldCB1cGRhdGUKICAgIGFwdC1nZXQgaW5zdGFsbCAteSB4ZmNlNCB4ZmNlNC1nb29kaWVzIHhyZHAgZGJ1cy14MTEKfQppbnN0YWxsX2RuZigpIHsKICAgIGRuZiBpbnN0YWxsIC15IHhyZHAgeG9yZ3hyZHAKICAgIGRuZiBncm91cCBpbnN0YWxsIC15ICJYZmNlIERlc2t0b3AiIFwKICAgICAgfHwgZG5mIGdyb3VwaW5zdGFsbCAteSAiWGZjZSIgXAogICAgICB8fCBkbmYgaW5zdGFsbCAteSBAeGZjZS1kZXNrdG9w
>> "%DESKTMP%" echo LWVudmlyb25tZW50Cn0KaW5zdGFsbF95dW0oKSB7CiAgICB5dW0gaW5zdGFsbCAteSBlcGVsLXJlbGVhc2UgfHwgdHJ1ZQogICAgeXVtIGdyb3VwaW5zdGFsbCAteSAiWGZjZSIgfHwgdHJ1ZQogICAgeXVtIGluc3RhbGwgLXkgeHJkcAp9Cmluc3RhbGxfenlwcGVyKCkgewogICAgenlwcGVyIC0tbm9uLWludGVyYWN0aXZlIGluc3RhbGwgeHJkcAogICAgenlwcGVyIC0tbm9uLWludGVyYWN0aXZlIGluc3RhbGwgLXQgcGF0dGVybiB4ZmNlCn0KYXJjaF9rZXlyaW5nKCkgewogICAgIyBBIGJyYW5kLW5ldyBBcmNoIHNldHMgdXAgcGFjbWFuJ3Mgc2lnbmluZyBrZXlzIGluIGl0cyBmaXJzdC1ydW4gc2NyaXB0LAogICAgIyB3aGljaCBuZXZlciBydW5zIHdoZW4gdGhlIHBhbmVsIGluc3RhbGxzIHdpdGggLS1uby1sYXVuY2guIFdpdGggbm8ga2V5cwogICAgIyBldmVyeSBkb3dubG9hZCBmYWlscyAoImtleXJpbmcgaXMgbm90IHdyaXRhYmxlIiksIHNvIHNldCB0aGVtIHVwIGhlcmUuCiAgICBpZiAhIHBhY21hbi1rZXkgLS1saXN0LWtleXMgMj4vZGV2L251bGwgfCBncmVwIC1xICdecHViJzsgdGhlbgogICAgICAgIGVjaG8gIlNldHRpbmcgdXAgcGFjbWFuJ3Mgc2lnbmluZyBrZXlzIChmaXJzdCBydW4pLi4uIgogICAgICAgIHBhY21hbi1rZXkgLS1pbml0ID4vZGV2L251bGwgMj4mMQogICAgICAgIHBhY21hbi1rZXkgLS1wb3B1bGF0ZSBhcmNobGludXggPi9kZXYvbnVsbCAyPiYxCiAgICBmaQp9Cmluc3RhbGxfcGFj
>> "%DESKTMP%" echo bWFuKCkgewogICAgYXJjaF9rZXlyaW5nCiAgICAjIC1TeXUsIG5ldmVyIC1TeSBhbG9uZTogcmVmcmVzaGluZyB0aGUgcGFja2FnZSBsaXN0IHdpdGhvdXQgdXBncmFkaW5nCiAgICAjIChhICJwYXJ0aWFsIHVwZ3JhZGUiKSBjYW4gYnJlYWsgYW4gQXJjaCBzeXN0ZW0uCiAgICBwYWNtYW4gLVN5dSAtLW5lZWRlZCAtLW5vY29uZmlybSBiYXNlLWRldmVsIGdpdCBzdWRvIHhmY2U0IHhvcmctc2VydmVyCiAgICAjIHhyZHAgKyB4b3JneHJkcCBhcmUgbm90IGluIEFyY2gncyBvZmZpY2lhbCByZXBvcyAtIHRoZXkgbGl2ZSBpbiB0aGUgQVVSCiAgICAjIChjb21tdW5pdHkgYnVpbGQgcmVjaXBlcykuIG1ha2Vwa2cgcmVmdXNlcyB0byBidWlsZCBhcyByb290LCBzbyBhCiAgICAjIHRlbXBvcmFyeSB1c2VyICJhdXJidWlsZCIgYnVpbGRzIHRoZW07IGl0cyBzdWRvIHJ1bGUgb25seSBhbGxvd3MgcGFjbWFuCiAgICAjICh0byBpbnN0YWxsIGJ1aWxkIGRlcGVuZGVuY2llcykgYW5kIGJvdGggYXJlIHJlbW92ZWQgYWZ0ZXJ3YXJkcy4KICAgICMgLXIgPSBzeXN0ZW0gdXNlciwgc28gaXQgbmV2ZXIgdGFrZXMgdXNlciBJRCAxMDAwIChyZXNlcnZlZCBmb3IgdGhlCiAgICAjIHBlcnNvbidzIG93biBmaXJzdCBhY2NvdW50KS4KICAgIGlkIC11IGF1cmJ1aWxkID4vZGV2L251bGwgMj4mMSB8fCB1c2VyYWRkIC1yIC1tIC1zIC9iaW4vYmFzaCBhdXJidWlsZAogICAgZWNobyAnYXVyYnVpbGQgQUxMPShBTEwpIE5PUEFTU1dEOiAv
>> "%DESKTMP%" echo dXNyL2Jpbi9wYWNtYW4nID4gL2V0Yy9zdWRvZXJzLmQvOTktYXVyYnVpbGQKICAgIGNobW9kIDQ0MCAvZXRjL3N1ZG9lcnMuZC85OS1hdXJidWlsZAogICAgYXVyX29rPTEKICAgIGZvciBwa2cgaW4geHJkcCB4b3JneHJkcDsgZG8KICAgICAgICBwYWNtYW4gLVEgIiRwa2ciID4vZGV2L251bGwgMj4mMSAmJiBjb250aW51ZQogICAgICAgIGVjaG8gIkJ1aWxkaW5nICRwa2cgZnJvbSB0aGUgQVVSICh0aGUgc2xvdyBwYXJ0IC0gc2V2ZXJhbCBtaW51dGVzKS4uLiIKICAgICAgICAjIFJ1bnMgYXMgYXVyYnVpbGQuIEJlZm9yZSBidWlsZGluZywgZmV0Y2ggdGhlIGRldmVsb3BlcnMnIHNpZ25pbmcKICAgICAgICAjIGtleXMgbGlzdGVkIGluIHRoZSByZWNpcGUgKHZhbGlkcGdwa2V5cykgc28gbWFrZXBrZyBjYW4gdmVyaWZ5IHRoZQogICAgICAgICMgZG93bmxvYWRlZCBzb3VyY2UuIC0tbm9jaGVjayBza2lwcyB4cmRwJ3Mgc2VsZi10ZXN0czogYSBmZXcKICAgICAgICAjIGxvZ2luLXNjcmVlbiBpbWFnZS1zY2FsaW5nIHRlc3RzIGZhaWwgYWdhaW5zdCBBcmNoJ3MgbmV3ZXIgaW1saWIyCiAgICAgICAgIyBhbHRob3VnaCB4cmRwIHdvcmtzIGZpbmUuCiAgICAgICAgc3VkbyAtdSBhdXJidWlsZCBiYXNoIC1zIC0tICIkcGtnIiA8PCdCVUlMRCcgfHwgeyBhdXJfb2s9MDsgYnJlYWs7IH0Kc2V0IC1lCmNkIH4gJiYgcm0gLXJmICIkMSIKZ2l0IGNsb25lIC0tZGVwdGggMSAiaHR0cHM6Ly9hdXIuYXJjaGxpbnV4Lm9yZy8k
>> "%DESKTMP%" echo MS5naXQiCmNkICIkMSIKa2V5cz0kKC4gLi9QS0dCVUlMRCA+L2Rldi9udWxsIDI+JjE7IGVjaG8gIiR7dmFsaWRwZ3BrZXlzW0BdfSIpCmlmIFsgLW4gIiRrZXlzIiBdOyB0aGVuCiAgICBncGcgLS1rZXlzZXJ2ZXIgaGtwczovL2tleXNlcnZlci51YnVudHUuY29tIC0tcmVjdi1rZXlzICRrZXlzCmZpCm1ha2Vwa2cgLXNpIC0tbm9jb25maXJtIC0tbm9jaGVjawpCVUlMRAogICAgZG9uZQogICAgcm0gLWYgL2V0Yy9zdWRvZXJzLmQvOTktYXVyYnVpbGQKICAgICMgZ3BnIGxlYXZlcyBoZWxwZXIgcHJvY2Vzc2VzIChncGctYWdlbnQsIGRpcm1uZ3IpIHJ1bm5pbmcgYXMgYXVyYnVpbGQsCiAgICAjIGFuZCB1c2VyZGVsIHJlZnVzZXMgdG8gcmVtb3ZlIGEgdXNlciB0aGF0IHN0aWxsIGhhcyBwcm9jZXNzZXMuCiAgICBwa2lsbCAtdSBhdXJidWlsZCA+L2Rldi9udWxsIDI+JjE7IHNsZWVwIDEKICAgIHVzZXJkZWwgLXIgYXVyYnVpbGQgPi9kZXYvbnVsbCAyPiYxIHx8IHRydWUKICAgIGlmIFsgIiRhdXJfb2siICE9IDEgXTsgdGhlbgogICAgICAgIGVjaG8gIkFVUl9CVUlMRF9GQUlMRUQiCiAgICAgICAgZXhpdCAyMAogICAgZmkKICAgICMgTGV0IHhyZHAncyBzZXNzaW9uIG1hbmFnZXIgc3RhcnQgWG9yZyAoQXJjaCdzIGRlZmF1bHQgb25seSBhbGxvd3MgYQogICAgIyBjb25zb2xlIGxvZ2luIHRvKSAtIG90aGVyd2lzZSB0aGUgUkRQIHdpbmRvdyBzdGF5cyBibGFjay4KICAgIGVjaG8gJ2FsbG93ZWRfdXNlcnM9YW55
>> "%DESKTMP%" echo Ym9keScgPiAvZXRjL1gxMS9Yd3JhcHBlci5jb25maWcKICAgICMgU3RhcnQgeHJkcCBhdXRvbWF0aWNhbGx5IGV2ZXJ5IHRpbWUgdGhpcyBkaXN0cm8gYm9vdHMgKHN5c3RlbWQpLgogICAgc3lzdGVtY3RsIGVuYWJsZSB4cmRwIHhyZHAtc2VzbWFuID4vZGV2L251bGwgMj4mMSB8fCB0cnVlCn0KCiMgRnJlc2ggQXJjaCBpbWFnZXMgaGF2ZSBubyBsYW5ndWFnZSBnZW5lcmF0ZWQsIHNvIGV2ZXJ5IHByb2dyYW0gcHJpbnRzCiMgIlNldHRpbmcgbG9jYWxlIGZhaWxlZCIgd2FybmluZ3MuIEdlbmVyYXRlIEVuZ2xpc2ggKFVURi04KSBmaXJzdCBpZiBpdCBpcwojIG1pc3NpbmcgKGJlc3QtZWZmb3J0OyBza2lwcGVkIHdoZXJlIGxvY2FsZS1nZW4gZG9lcyBub3QgZXhpc3QpLgppZiBbIC1mIC9ldGMvbG9jYWxlLmdlbiBdICYmICEgbG9jYWxlIC1hIDI+L2Rldi9udWxsIHwgZ3JlcCAtcWkgJ15lbl9VU1wudXRmOCQnOyB0aGVuCiAgICBzZWQgLWkgJ3MvXiNlbl9VUy5VVEYtOC9lbl9VUy5VVEYtOC8nIC9ldGMvbG9jYWxlLmdlbgogICAgbG9jYWxlLWdlbiA+L2Rldi9udWxsIDI+JjEgfHwgdHJ1ZQpmaQoKIyAtLS0gUGljayB0aGUgcGFja2FnZSBtYW5hZ2VyIGFuZCBpbnN0YWxsICh0aGlzIHBhcnQgbXVzdCBzdWNjZWVkKSAtLS0Kc2V0IC1lCmlmIGNvbW1hbmQgLXYgYXB0LWdldCA+L2Rldi9udWxsIDI+JjE7ICAgdGhlbiBQTT1hcHQ7ICAgIGVjaG8gIlBhY2thZ2UgbWFuYWdlcjogYXB0IjsgICAgaW5zdGFsbF9hcHQK
>> "%DESKTMP%" echo ZWxpZiBjb21tYW5kIC12IGRuZiAgID4vZGV2L251bGwgMj4mMTsgICB0aGVuIFBNPWRuZjsgICAgZWNobyAiUGFja2FnZSBtYW5hZ2VyOiBkbmYiOyAgICBpbnN0YWxsX2RuZgplbGlmIGNvbW1hbmQgLXYgenlwcGVyID4vZGV2L251bGwgMj4mMTsgIHRoZW4gUE09enlwcGVyOyBlY2hvICJQYWNrYWdlIG1hbmFnZXI6IHp5cHBlciI7IGluc3RhbGxfenlwcGVyCmVsaWYgY29tbWFuZCAtdiB5dW0gICA+L2Rldi9udWxsIDI+JjE7ICAgdGhlbiBQTT15dW07ICAgIGVjaG8gIlBhY2thZ2UgbWFuYWdlcjogeXVtIjsgICAgaW5zdGFsbF95dW0KZWxpZiBjb21tYW5kIC12IHBhY21hbiA+L2Rldi9udWxsIDI+JjE7ICB0aGVuIFBNPXBhY21hbjsgZWNobyAiUGFja2FnZSBtYW5hZ2VyOiBwYWNtYW4iOyBpbnN0YWxsX3BhY21hbgplbHNlCiAgICBlY2hvICJVTktOT1dOX1BLR19NQU5BR0VSIgogICAgZXhpdCAyMQpmaQpzZXQgK2UKCiMgLS0tIEV2ZXJ5dGhpbmcgYmVsb3cgaXMgYmVzdC1lZmZvcnQgY29uZmlndXJhdGlvbiAobmV2ZXIgZmFpbHMgdGhlIGluc3RhbGwpIC0tLQoKIyBQb2ludCB4cmRwIGF0IHBvcnQgMzM5MCAodGhlIHBvcnQgdGhlIHBhbmVsJ3MgUmVtb3RlIERlc2t0b3AgY29ubmVjdHMgdG8pLgppZiBbIC1mIC9ldGMveHJkcC94cmRwLmluaSBdOyB0aGVuCiAgICBzZWQgLWkgJ3MvXnBvcnQ9MzM4OS9wb3J0PTMzOTAvJyAvZXRjL3hyZHAveHJkcC5pbmkKICAgIGdyZXAgLXEgJ15wb3J0PTMzOTAnIC9ldGMv
>> "%DESKTMP%" echo eHJkcC94cmRwLmluaSBcCiAgICAgIHx8IHNlZCAtaSAnMCwvXlxbR2xvYmFsc1xdL3MvL1tHbG9iYWxzXVxucG9ydD0zMzkwLycgL2V0Yy94cmRwL3hyZHAuaW5pCmZpCgojIE1ha2UgWEZDRSB0aGUgZGVmYXVsdCBzZXNzaW9uIGZvciBjdXJyZW50IGFuZCBmdXR1cmUgdXNlcnMuCiMgKC54c2Vzc2lvbiBpcyByZWFkIG9uIERlYmlhbi9GZWRvcmEvb3BlblNVU0UsIC54aW5pdHJjIG9uIEFyY2guKQpta2RpciAtcCAvZXRjL3NrZWwKZm9yIGYgaW4gLnhzZXNzaW9uIC54aW5pdHJjOyBkbwogICAgZWNobyAnZXhlYyBzdGFydHhmY2U0JyA+ICIvZXRjL3NrZWwvJGYiCiAgICBmb3IgaCBpbiAvcm9vdCAvaG9tZS8qOyBkbwogICAgICAgIFsgLWQgIiRoIiBdIHx8IGNvbnRpbnVlCiAgICAgICAgZWNobyAnZXhlYyBzdGFydHhmY2U0JyA+ICIkaC8kZiIKICAgICAgICBjaG93biAtLXJlZmVyZW5jZT0iJGgiICIkaC8kZiIgMj4vZGV2L251bGwgfHwgdHJ1ZQogICAgZG9uZQpkb25lCgojIERlYmlhbiB3YW50cyB0aGUgeHJkcCB1c2VyIGluIHNzbC1jZXJ0OyBoYXJtbGVzcyBpZiBhYnNlbnQgZWxzZXdoZXJlLgpnZXRlbnQgZ3JvdXAgc3NsLWNlcnQgPi9kZXYvbnVsbCAyPiYxICYmIHVzZXJtb2QgLWFHIHNzbC1jZXJ0IHhyZHAgMj4vZGV2L251bGwgfHwgdHJ1ZQoKIyAoUmUpc3RhcnQgeHJkcCBub3c6IFN5c1Ygc2VydmljZSwgZWxzZSBzeXN0ZW1kLCBlbHNlIHRoZSBiaW5hcmllcyBkaXJlY3RseQojIChXU0wgZGlzdHJv
>> "%DESKTMP%" echo cyBvZnRlbiBydW4gd2l0aG91dCBzeXN0ZW1kLCBzbyBmYWxsIGFsbCB0aGUgd2F5IHRocm91Z2gpLgojIFJFU1RBUlQsIG5vdCBzdGFydDogYXB0IHN0YXJ0cyB4cmRwIHRoZSBtb21lbnQgaXQgaXMgaW5zdGFsbGVkIC0gb24gdGhlCiMgZGVmYXVsdCBwb3J0IDMzODksIGJlZm9yZSB0aGUgcG9ydD0zMzkwIGVkaXQgYWJvdmUgLSBhbmQgYSBwbGFpbiAic3RhcnQiCiMgbGVhdmVzIHRoYXQgYWxyZWFkeS1ydW5uaW5nIGNvcHkgbGlzdGVuaW5nIG9uIHRoZSB3cm9uZyBwb3J0LgppZiBzZXJ2aWNlIHhyZHAgcmVzdGFydCA+L2Rldi9udWxsIDI+JjE7IHRoZW4KICAgIDoKZWxpZiBzeXN0ZW1jdGwgcmVzdGFydCB4cmRwLXNlc21hbiB4cmRwID4vZGV2L251bGwgMj4mMTsgdGhlbgogICAgOgplbHNlCiAgICBwa2lsbCAteCB4cmRwID4vZGV2L251bGwgMj4mMTsgcGtpbGwgLXggeHJkcC1zZXNtYW4gPi9kZXYvbnVsbCAyPiYxOyBzbGVlcCAxCiAgICAoL3Vzci9zYmluL3hyZHAtc2VzbWFuID4vZGV2L251bGwgMj4mMSAmKQogICAgc2xlZXAgMQogICAgKC91c3Ivc2Jpbi94cmRwID4vZGV2L251bGwgMj4mMSAmKQpmaQoKZWNobyBERVNLX1NFVFVQX0RPTkUKZXhpdCAwCg==
wsl -d !sel! -u root -- bash -c "tr -d '\r' | base64 -d > /tmp/wsl-desktop-setup.sh && bash /tmp/wsl-desktop-setup.sh </dev/null" < "%DESKTMP%"
set "deskrc=!errorlevel!"
del "%DESKTMP%" >nul 2>&1
if not "!deskrc!"=="0" goto INSTALL_DESKTOP_FAIL
echo.
echo  Done. XFCE + xrdp installed and set to port 3390.
echo  Opening the desktop now...
timeout /t 2 /nobreak >nul
goto OPEN_DESKTOP

:INSTALL_DESKTOP_KEX
echo.
echo  Installing kali-win-kex on !sel! (this can take several minutes)...
echo.
wsl -d !sel! -u root -- bash -lc "set -e; export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y kali-win-kex" <nul
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
echo    - Arch: building xrdp from the AUR failed - it prints
echo      AUR_BUILD_FAILED above, with the build error just before it
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
REM  With no account chosen, kex runs as the distro's default user. A Kali
REM  downloaded by the panel (--no-launch) has no normal user until one is
REM  made, so that default is root - and Win-KeX refuses to run as root.
REM  Say so plainly instead of letting kex fail with a confusing error.
if not defined acctuser (
    set "kexuid="
    for /f "usebackq delims=" %%i in (`wsl -d !sel! -e id -u 2^>nul ^<nul`) do set "kexuid=%%i"
    if "!kexuid!"=="0" (
        echo.
        echo  The Kali desktop ^(Win-KeX^) cannot run as root, and !sel! has no
        echo  normal user as its default login yet. Fix: Open it, choose [A] Add
        echo  an account, answer Y, then open the Desktop using that account.
        pause >nul
        goto DISTRO_MENU
    )
)
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
wsl -d !sel! -u root -- bash -c "echo '!KA_B64!' | base64 -d > /usr/local/bin/xrdp-keepalive.sh && chmod +x /usr/local/bin/xrdp-keepalive.sh" <nul
powershell -NoProfile -Command "Start-Process wsl -ArgumentList '-d','!sel!','-u','root','--','/usr/local/bin/xrdp-keepalive.sh' -WindowStyle Hidden" <nul

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
wsl --unregister !sel! <nul
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
wsl --install !newd! --location "!loc!" --no-launch <nul
REM  WSL reports its own errors as NEGATIVE exit codes, which "if errorlevel 1"
REM  misses - so compare with 0 (e.g. "connection was reset" mid-download).
if not "!errorlevel!"=="0" goto DOWNLOAD_FAILED
goto DOWNLOAD_DONE

:DOWNLOAD_FAILED
echo.
echo  The download/install FAILED - see the message above. Common causes:
echo    - the server dropped the connection partway ("connection was reset").
echo      Debian's server does this often - the resumable download below
echo      gets past it.
echo    - the name was typed wrong: it must match the first column exactly
echo    - a distro with that name is already installed
echo.
echo    [Y] Try a RESUMABLE download - fetches the same official file from
echo        Microsoft's list in pieces, continuing wherever the connection
echo        drops, checks its fingerprint (SHA-256), then installs it
echo    [N] Back to the main menu
echo.
set "rt="
set /p "rt=Try the resumable download? (Y/N): "
if /i not "!rt!"=="Y" goto MAIN
echo.
REM  The fallback is a PowerShell script carried as -EncodedCommand (base64 of
REM  UTF-16 text) so no quoting can mangle it. It reads the distro name and
REM  folder from the newd / loc variables, uses the built-in curl.exe with
REM  resume (-C -), verifies the SHA-256 from Microsoft's catalog, then runs
REM  "wsl --install --from-file". Exit 0 = installed.
set "RESUME_PS=JABFAHIAcgBvAHIAQQBjAHQAaQBvAG4AUAByAGUAZgBlAHIAZQBuAGMAZQAgAD0AIAAnAFMAdABvAHAAJwAKACQAbgBhAG0AZQAgAD0AIAAkAGUAbgB2ADoAbgBlAHcAZAA7ACAAJABsAG8AYwAgAD0AIAAkAGUAbgB2ADoAbABvAGMACgB0AHIAeQAgAHsACgAkAGoAIAA9ACAASQBuAHYAbwBrAGUALQBSAGUAcwB0AE0AZQB0AGgAbwBkACAAJwBoAHQAdABwAHMAOgAvAC8AcgBhAHcALgBnAGkAdABoAHUAYgB1AHMAZQByAGMAbwBuAHQAZQBuAHQALgBjAG8AbQAvAG0AaQBjAHIAbwBzAG8AZgB0AC8AVwBTAEwALwBtAGEAcwB0AGUAcgAvAGQAaQBzAHQAcgBpAGIAdQB0AGkAbwBuAHMALwBEAGkAcwB0AHIAaQBiAHUAdABpAG8AbgBJAG4AZgBvAC4AagBzAG8AbgAnAAoAfQAgAGMAYQB0AGMAaAAgAHsAIABXAHIAaQB0AGUALQBIAG8AcwB0ACAAJwAgAEMAbwB1AGwAZAAgAG4AbwB0ACAAcgBlAGEAZAAgAE0AaQBjAHIAbwBzAG8AZgB0ACcAJwBzACAAZABpAHMAdAByAG8AIABsAGkAcwB0ACAAKABuAG8AIABpAG4AdABlAHIAbgBlAHQAPwApAC4AJwA7ACAAZQB4AGkAdAAgADIAIAB9AAoAJABkACAAPQAgACQAagAuAE0AbwBkAGUAcgBuAEQAaQBzAHQAcgBpAGIAdQB0AGkAbwBuAHMALgBQAFMATwBiAGoAZQBjAHQALgBQAHIAbwBwAGUAcgB0AGkAZQBzAC4AVgBhAGwAdQBlACAAfAAgAEYAbwByAEUAYQBjAGgALQBPAGIAagBlAGMAdAAgAHsAIAAkAF8AIAB9ACAAfAAgAFcAaABlAHIAZQAtAE8AYgBqAGUAYwB0ACAAewAgACQAXwAuAE4AYQBtAGUAIAAtAGUAcQAgACQAbgBhAG0AZQAgAH0AIAB8ACAAUwBlAGwAZQBjAHQALQBPAGIAagBlAGMAdAAgAC0ARgBpAHIAcwB0ACAAMQAKAGkAZgAgACgALQBuAG8AdAAgACQAZAApACAAewAgAFcAcgBpAHQAZQAtAEgAbwBzAHQAIAAiACAAJwAkAG4AYQBtAGUAJwAgAGgAYQBzACAAbgBvACAAZABvAHcAbgBsAG8AYQBkAGEAYgBsAGUAIABpAG0AYQBnAGUAIABpAG4AIABNAGkAYwByAG8AcwBvAGYAdAAnAHMAIABsAGkAcwB0AC4AIgA7ACAAZQB4AGkAdAAgADIAIAB9AAoAJABrAGUAeQAgAD0AIAAnAEEAbQBkADYANABVAHIAbAAnADsAIABpAGYAIAAoACQAZQBuAHYAOgBQAFIATwBDAEUAUwBTAE8AUgBfAEEAUgBDAEgASQBUAEUAQwBUAFUAUgBFACAALQBlAHEAIAAnAEEAUgBNADYANAAnACkAIAB7ACAAJABrAGUAeQAgAD0AIAAnAEEAcgBtADYANABVAHIAbAAnACAAfQAKACQAdQByAGwAIAA9ACAAJABkAC4AJABrAGUAeQAuAFUAcgBsADsAIAAkAHMAaABhACAAPQAgACgAJABkAC4AJABrAGUAeQAuAFMAaABhADIANQA2ACAALQByAGUAcABsAGEAYwBlACAAJwBeADAAeAAnACwAIAAnACcAKQAKACQAZgBpAGwAZQAgAD0AIABKAG8AaQBuAC0AUABhAHQAaAAgACQAZQBuAHYAOgBUAEUATQBQACAAIgAkAG4AYQBtAGUALgB3AHMAbAAiAAoAUgBlAG0AbwB2AGUALQBJAHQAZQBtACAALQBMAGkAdABlAHIAYQBsAFAAYQB0AGgAIAAkAGYAaQBsAGUAIAAtAEUAcgByAG8AcgBBAGMAdABpAG8AbgAgAFMAaQBsAGUAbgB0AGwAeQBDAG8AbgB0AGkAbgB1AGUACgBXAHIAaQB0AGUALQBIAG8AcwB0ACAAIgAgAEQAbwB3AG4AbABvAGEAZABpAG4AZwAgACQAdQByAGwAIgAKAFcAcgBpAHQAZQAtAEgAbwBzAHQAIAAnACAAKAByAGUAcwB1AG0AYQBiAGwAZQA6ACAAaQBmACAAdABoAGUAIABzAGUAcgB2AGUAcgAgAGQAcgBvAHAAcwAgAHQAaABlACAAYwBvAG4AbgBlAGMAdABpAG8AbgAsACAAaQB0ACAAYwBvAG4AdABpAG4AdQBlAHMAIAB3AGgAZQByAGUAIABpAHQAIABzAHQAbwBwAHAAZQBkACkAJwAKACQAbwBrACAAPQAgACQAZgBhAGwAcwBlAAoAZgBvAHIAIAAoACQAaQAgAD0AIAAxADsAIAAkAGkAIAAtAGwAZQAgADYAMAA7ACAAJABpACsAKwApACAAewAKACYAIABjAHUAcgBsAC4AZQB4AGUAIAAtAEwAIAAtAEMAIAAtACAALQBzAFMAIAAtAC0AbQBhAHgALQB0AGkAbQBlACAAMwAwADAAIAAtAG8AIAAkAGYAaQBsAGUAIAAkAHUAcgBsAAoAaQBmACAAKAAkAEwAQQBTAFQARQBYAEkAVABDAE8ARABFACAALQBlAHEAIAAwACkAIAB7ACAAJABvAGsAIAA9ACAAJAB0AHIAdQBlADsAIABiAHIAZQBhAGsAIAB9AAoAVwByAGkAdABlAC0ASABvAHMAdAAgACIAIAAgACAAYwBvAG4AbgBlAGMAdABpAG8AbgAgAGQAcgBvAHAAcABlAGQAIAAtACAAcgBlAHMAdQBtAGkAbgBnACAAKABhAHQAdABlAG0AcAB0ACAAJABpACAAbwBmACAANgAwACkALgAuAC4AIgAKAH0ACgBpAGYAIAAoAC0AbgBvAHQAIAAkAG8AawApACAAewAgAFcAcgBpAHQAZQAtAEgAbwBzAHQAIAAnACAARABvAHcAbgBsAG8AYQBkACAAZABpAGQAIABuAG8AdAAgAGMAbwBtAHAAbABlAHQAZQAuACcAOwAgAGUAeABpAHQAIAAzACAAfQAKAGkAZgAgACgAKABHAGUAdAAtAEYAaQBsAGUASABhAHMAaAAgAC0ATABpAHQAZQByAGEAbABQAGEAdABoACAAJABmAGkAbABlACAALQBBAGwAZwBvAHIAaQB0AGgAbQAgAFMASABBADIANQA2ACkALgBIAGEAcwBoACAALQBuAGUAIAAkAHMAaABhACkAIAB7AAoAUgBlAG0AbwB2AGUALQBJAHQAZQBtACAALQBMAGkAdABlAHIAYQBsAFAAYQB0AGgAIAAkAGYAaQBsAGUAIAAtAEUAcgByAG8AcgBBAGMAdABpAG8AbgAgAFMAaQBsAGUAbgB0AGwAeQBDAG8AbgB0AGkAbgB1AGUACgBXAHIAaQB0AGUALQBIAG8AcwB0ACAAJwAgAFQAaABlACAAZABvAHcAbgBsAG8AYQBkAGUAZAAgAGYAaQBsAGUAIABpAHMAIABkAGEAbQBhAGcAZQBkACAAKABmAGkAbgBnAGUAcgBwAHIAaQBuAHQAIABtAGkAcwBtAGEAdABjAGgAKQAgAC0AIABuAG8AdAAgAGkAbgBzAHQAYQBsAGwAZQBkAC4AJwA7ACAAZQB4AGkAdAAgADQACgB9AAoAVwByAGkAdABlAC0ASABvAHMAdAAgACcAIABEAG8AdwBuAGwAbwBhAGQAIAB2AGUAcgBpAGYAaQBlAGQALgAgAEkAbgBzAHQAYQBsAGwAaQBuAGcALgAuAC4AJwAKACYAIAB3AHMAbAAuAGUAeABlACAALQAtAGkAbgBzAHQAYQBsAGwAIAAtAC0AZgByAG8AbQAtAGYAaQBsAGUAIAAkAGYAaQBsAGUAIAAtAC0AbgBhAG0AZQAgACQAbgBhAG0AZQAgAC0ALQBsAG8AYwBhAHQAaQBvAG4AIAAkAGwAbwBjACAALQAtAG4AbwAtAGwAYQB1AG4AYwBoAAoAJABjAG8AZABlACAAPQAgACQATABBAFMAVABFAFgASQBUAEMATwBEAEUACgBSAGUAbQBvAHYAZQAtAEkAdABlAG0AIAAtAEwAaQB0AGUAcgBhAGwAUABhAHQAaAAgACQAZgBpAGwAZQAgAC0ARQByAHIAbwByAEEAYwB0AGkAbwBuACAAUwBpAGwAZQBuAHQAbAB5AEMAbwBuAHQAaQBuAHUAZQAKAGkAZgAgACgAJABjAG8AZABlACAALQBuAGUAIAAwACkAIAB7ACAAZQB4AGkAdAAgADUAIAB9AAoAZQB4AGkAdAAgADAA"
powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand !RESUME_PS! <nul
if not "!errorlevel!"=="0" (
    echo.
    echo  The resumable download did not work either - see the message above.
    echo  Check your internet connection and try [N] again later.
    pause >nul
    goto MAIN
)

:DOWNLOAD_DONE
echo.
echo  Finished. To set it up, pick it from the list, choose Open, then
echo  [A] Add an account and answer Y - that creates your Linux username
echo  and password. (Ubuntu/Debian also ask for one the first time you open
echo  a Terminal; Arch and some others do not ask - they start as root.)
pause >nul
goto MAIN


:BACKUP
REM  ================================================================
REM  Back up one distro into a single .tar file with "wsl --export".
REM  The file holds EVERYTHING inside that Linux: installed programs, the
REM  desktop setup, users, home folders. Restore it with [R] - on this PC
REM  or a new one - and it comes back exactly as it was.
REM  ================================================================
cls
echo ================================================================
echo                   Back up a distro  (wsl --export)
echo ================================================================
echo.
if !count!==0 (
    echo  No distros installed - nothing to back up.
    pause >nul
    goto MAIN
)
echo  Which distro should be backed up?
for /l %%i in (1,1,!count!) do echo     [%%i] !distro[%%i]!
echo     [B] Back
echo.
set "bsel="
set /p "bsel=Enter your choice: "
if /i "!bsel!"=="B" goto MAIN
if not defined distro[!bsel!] (
    echo  Invalid choice. Press any key.
    pause >nul
    goto BACKUP
)
for %%c in (!bsel!) do set "bname=!distro[%%c]!"
REM  Date+time in the file name (YYYY-MM-DD_HHMM) so backups sort in order and
REM  never overwrite each other. Asked from PowerShell because cmd's %date%
REM  format changes with the Windows language/region settings.
for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmm"`) do set "stamp=%%t"
echo.
echo  Where should the backup be saved?
echo    - Press ENTER for the default folder:  !BACKUP_BASE!
echo    - Or type another folder, e.g. E:\ for a USB drive
echo.
set "bdir=!BACKUP_BASE!"
set /p "bdir=Backup folder [!BACKUP_BASE!]: "
if not defined bdir set "bdir=!BACKUP_BASE!"
set "bdir=!bdir:"=!"
if "!bdir:~-1!"=="\" set "bdir=!bdir:~0,-1!"
set "bfile=!bdir!\!bname!_!stamp!.tar"
echo.
echo  This will:
echo    1. STOP !bname! so no file changes mid-copy (an open desktop or
echo       terminal for it will close - save your work first).
echo    2. Save it all to:  !bfile!
echo  The file can be several GB and take a few minutes. Your distro is
echo  not changed or removed.
echo.
set "ok="
set /p "ok=Start the backup? (Y/N): "
if /i not "!ok!"=="Y" goto MAIN
if not exist "!bdir!" mkdir "!bdir!" 2>nul
echo.
REM  Only stop it if it is running - checking for Kali's desktop on a stopped
REM  distro would boot it first. "<nul" stops wsl from reading the keyboard,
REM  so it can never swallow what you type next.
set "brun=0"
for /f "usebackq delims=" %%r in (`wsl --list --running --quiet`) do if /i "%%r"=="!bname!" set "brun=1"
if "!brun!"=="1" (
    echo  Stopping !bname! ...
    call :STOP_KEX "!bname!"
    wsl --terminate !bname! <nul >nul 2>&1
)
echo  Exporting - please wait...
wsl --export !bname! "!bfile!" <nul
REM  WSL reports its own errors as NEGATIVE exit codes, which "if errorlevel 1"
REM  (meaning 1 or more) misses - so compare with 0 and also check the file.
set "xrc=!errorlevel!"
if not exist "!bfile!" set "xrc=1"
if not "!xrc!"=="0" (
    del "!bfile!" >nul 2>&1
    echo.
    echo  The backup FAILED - see the message above. Common causes: not enough
    echo  free space in !bdir!, or that folder cannot be written to.
    pause >nul
    goto MAIN
)
set "bsize="
for /f "usebackq delims=" %%s in (`powershell -NoProfile -Command "'{0:N2} GB' -f ((Get-Item -LiteralPath '!bfile!').Length / 1GB)"`) do set "bsize=%%s"
echo.
echo  Done - backup saved (!bsize!):
echo    !bfile!
echo.
echo  To move this distro to another PC: copy that file over, put this panel
echo  on the new PC, and use [R] Restore.
echo  NOTE: saved panel accounts are NOT in the backup - their passwords are
echo  locked to this Windows login. On a new PC, re-add them with Open,
echo  [A], answering N (the Linux user already exists inside the backup).
pause >nul
call :FREEVM
goto MAIN


:RESTORE
REM  ================================================================
REM  Bring back a .tar backup as a distro with "wsl --import".
REM  Import always starts as root, so afterwards we set the normal user
REM  (the first regular account: Linux user ID 1000 or above) as the
REM  default login with "wsl --manage <name> --set-default-user".
REM  ================================================================
cls
echo ================================================================
echo                  Restore a backup  (wsl --import)
echo ================================================================
echo.
echo  Backups found in !BACKUP_BASE!  (newest first):
set rb=0
if exist "!BACKUP_BASE!\*.tar" (
    for /f "delims=" %%f in ('dir /b /o-d "!BACKUP_BASE!\*.tar"') do (
        set /a rb+=1
        set "bk[!rb!]=!BACKUP_BASE!\%%f"
        set "bkn[!rb!]=%%f"
    )
)
if !rb!==0 echo     (none there)
for /l %%i in (1,1,!rb!) do echo     [%%i] !bkn[%%i]!
echo.
echo     [P] Type the full path to a .tar file somewhere else (e.g. a USB)
echo     [B] Back
echo.
set "rsel="
set /p "rsel=Enter your choice: "
if /i "!rsel!"=="B" goto MAIN
set "rfile="
if /i "!rsel!"=="P" (
    set /p "rfile=Full path to the .tar file: "
    if defined rfile set "rfile=!rfile:"=!"
) else if defined bk[!rsel!] (
    for %%c in (!rsel!) do set "rfile=!bk[%%c]!"
)
if not defined rfile (
    echo  Invalid choice. Press any key.
    pause >nul
    goto RESTORE
)
if not exist "!rfile!" (
    echo.
    echo  File not found:  !rfile!
    pause >nul
    goto RESTORE
)
REM  Suggest the original distro name: the file name minus the _date_time
REM  part that [E] adds (e.g. archlinux_2026-09-25_1830.tar -> archlinux).
set "rdef="
for /f "usebackq delims=" %%n in (`powershell -NoProfile -Command "[IO.Path]::GetFileNameWithoutExtension('!rfile!') -replace '_\d{4}-\d{2}-\d{2}_\d{4}$',''"`) do set "rdef=%%n"
echo.
echo  What should the restored distro be called?
echo  It must be a name that is NOT already installed (no spaces).
set "rname=!rdef!"
set /p "rname=Distro name [!rdef!]: "
if not defined rname set "rname=!rdef!"
if not defined rname goto RESTORE
if not "!rname: =!"=="!rname!" (
    echo  Names cannot contain spaces. Press any key.
    pause >nul
    goto RESTORE
)
set "rexists=0"
for /f "usebackq delims=" %%d in (`wsl --list --quiet 2^>nul`) do if /i "%%d"=="!rname!" set "rexists=1"
if "!rexists!"=="1" (
    echo.
    echo  A distro called !rname! is already installed. Restore it under a
    echo  different name, e.g. !rname!-restored - or Delete the existing
    echo  one first if you really want to replace it.
    pause >nul
    goto RESTORE
)
echo.
echo  Where should it be installed?
echo    - Press ENTER for:  !WSL_BASE!\!rname!
echo    - Or type another folder
set "rloc=!WSL_BASE!\!rname!"
set /p "rloc=Install folder [!WSL_BASE!\!rname!]: "
if not defined rloc set "rloc=!WSL_BASE!\!rname!"
set "rloc=!rloc:"=!"
if exist "!rloc!\ext4.vhdx" (
    echo.
    echo  !rloc! already holds a distro disk ^(ext4.vhdx^). Pick another folder.
    pause >nul
    goto RESTORE
)
if not exist "!rloc!" mkdir "!rloc!" 2>nul
echo.
echo  Restoring !rname! from:
echo    !rfile!
echo  This can take a few minutes - please wait...
wsl --import !rname! "!rloc!" "!rfile!" <nul
REM  Negative WSL exit codes again - compare with 0, not "errorlevel 1".
if not "!errorlevel!"=="0" (
    echo.
    echo  The restore FAILED - see the message above. Common causes: not
    echo  enough free space, or the .tar file is incomplete/damaged.
    pause >nul
    goto MAIN
)
set "ruser="
for /f "usebackq delims=" %%u in (`wsl -d !rname! -u root -e sh -c "getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1; exit}'" 2^>nul ^<nul`) do set "ruser=%%u"
echo.
echo  Done - !rname! is restored with all its programs and files.
if defined ruser (
    wsl --manage !rname! --set-default-user !ruser! <nul >nul 2>&1
    echo  Default login set to "!ruser!" ^(the user found inside the backup^).
) else (
    echo  No normal user was found inside it, so it opens as root.
)
echo  It appears in the main list - pick it to Open it. Saved panel accounts
echo  are not part of a backup: if you need auto-login, use Open, [A], and
echo  answer N ^(the Linux user already exists^).
wsl --terminate !rname! <nul >nul 2>&1
pause >nul
call :FREEVM
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
wsl -d %~1 -- bash -lc "command -v kex >/dev/null 2>&1" <nul
if errorlevel 1 goto :eof
echo  Stopping Win-KeX on %~1 ...
wsl -d %~1 -- bash -lc "cd ~ && kex --stop >/dev/null 2>&1" <nul
goto :eof


:STOP_KEX_ALL
REM  Stop Win-KeX on every currently-running distro (before a full wsl --shutdown).
for /f "usebackq delims=" %%r in (`wsl --list --running --quiet`) do call :STOP_KEX "%%r"
goto :eof


:END
endlocal
exit /b
