# WSL Setup and Run Helper

A small Windows tool (a double-click `.bat` launcher plus a PowerShell script) that gives new users a **no-code, menu-driven way to
install and run Linux on Windows** through WSL (Windows Subsystem for Linux).

Double-click it on a brand-new PC and it installs WSL for you. On a PC that
already has WSL it becomes a control panel for your Linux distros: download,
open (desktop or terminal), back up, restore, close and delete them from one
menu.

No PowerShell knowledge needed, no memorized `wsl` commands.

My try to learn bash through a real-world working project.

---

## What it does

**First run on a fresh PC: it bootstraps WSL itself**
1. Detects that WSL isn't set up yet.
2. Asks once, then (through a Windows administrator/UAC prompt) turns on the
   required Windows features, installs the WSL platform and updates it.
3. Tells you if a **restart** is needed. After restarting, run it again and
   download your first Linux distro from the menu.

**Everyday use: a control panel for your distros**

| Key | Option | What happens behind the scenes |
|---|---|---|
| *Enter* | Quick-open | Wakes your default distro and opens its desktop with its first saved account |
| number | Manage a distro | Open (Desktop / Terminal), Close, Accounts, xrdp port, Compact disk, systemd on/off, or Delete it |
| `C` | Close a running distro | `wsl --terminate`, which frees its RAM |
| `S` | Shut down all WSL | `wsl --shutdown`, which frees the whole WSL VM |
| `N` | Download a new distro | `wsl --install` from Microsoft's official list, with a resumable fallback |
| `E` | Back up a distro | `wsl --export` saves everything to one `.tar` (or faster `.vhdx`) file |
| `R` | Restore a backup | `wsl --import` brings a backup back, on this PC or a new one |
| `K` | Compact a disk | Hands unused `ext4.vhdx` space back to Windows (admin, via diskpart) |
| `T` | Memory / CPU limits | Edits `.wslconfig` (a copy of the old file is kept as `.wslconfig.bak`) |
| `U` | Update / repair WSL | `wsl --update` (admin) |
| `Q` | Quit | Closes the panel; distros keep running |

- **Desktop or Terminal.** Kali opens in its own Win-KeX window. Every other
  distro opens in Windows Remote Desktop (xrdp, default port **3390** so it never
  clashes with Windows' own Remote Desktop on 3389). Each distro can have its own
  port, so two desktops can be open at once.
- **One-click desktop install.** If a distro has no desktop yet, the panel
  installs XFCE + xrdp for you. It auto-detects the package manager (apt / dnf
  / zypper / yum / pacman), and on Arch it builds xrdp from the AUR.
- **Saved accounts.** Store a Linux username + password per distro so the
  panel logs you in automatically. Passwords are **encrypted with Windows
  DPAPI**, never stored as plain text. On a fresh distro, adding an account
  also **creates that Linux user** with admin rights (`sudo` or `wheel`) and an
  XFCE session, so the first login just works. You can also change a password or
  remove a saved account. If a saved account's Linux user no longer exists (for
  example the distro was re-downloaded), the panel offers to create it again.
- **Backup & restore.** A backup holds *everything* inside the distro:
  programs, the desktop setup, users and files. Restoring it on a new laptop
  means no setting up again.
- **Keep-alive.** WSL normally shuts an idle distro down seconds after the
  launcher closes. The panel keeps it running while the desktop is in use.
- **Every menu explains itself.** Each option shows in one line what it does
  and which `wsl` command runs, so you learn the tool as you use it.

---

## Requirements

- Windows 10 (2004+) or Windows 11.
- Administrator access for the **one-time** WSL install/update (Windows shows a
  UAC prompt; the panel itself runs as a normal window).
- An internet connection to download WSL, distros and desktop packages.

---

## Quick start: your first Linux desktop

1. Copy this folder anywhere (keep `WSL-Control-Panel.bat`, `WSL-Control-Panel.ps1`
   and the `scripts` folder together) and double-click **`WSL-Control-Panel.bat`**.
   On a PC without WSL, allow the administrator prompt and restart if asked.
2. **`[N]` Download**: type a name from the list (e.g. `Ubuntu-24.04`,
   `Debian`, `archlinux`, `kali-linux`) and press Enter for the default folder.
3. **Create your login**: pick the distro by number, then **`[A]` Accounts**,
   **`[A]` Add an account**, and answer **Y**. Choose a username and password.
   The panel then shows each step while it creates the account (on Arch,
   installing `sudo` takes a minute or two).
4. **Open the desktop**: pick the distro, choose your account, then **`[1]`
   Desktop**. The first time, the panel says there's no desktop yet. Press
   **`[I]`** to install it. This takes 5–20 minutes (Arch is the slowest,
   because it compiles xrdp). Remote Desktop then opens and logs you in.
5. **Back it up** with **`[E]`** once it's set up the way you like.

## Moving to a new PC

1. On the old PC: **`[E]` Back up** the distro, then copy the `.tar` file (from
   `D:\Linux\Backups` or wherever you saved it) to a USB drive or cloud storage.
2. On the new PC: run the panel (it installs WSL if needed), then **`[R]`
   Restore**. Pick the backup (or `[P]` and type its path). The distro comes
   back exactly as it was, with your normal user as the default login.
3. Saved panel accounts are **not** in the backup, because their passwords are
   locked to the old Windows login. Re-add yours with Accounts, `[A]`, and answer
   **N** (the Linux user already exists inside the backup).

---

## Distro compatibility

Terminal, close, delete, backup and restore use plain `wsl` commands and work
with **every** distro. The desktop setup is distro-specific:

| Distro (name in `wsl --list --online`) | Desktop | Status |
|---|---|---|
| `Ubuntu-24.04` | XFCE + xrdp | ✅ Tested: account, desktop install, xrdp on 3390 |
| `Debian` | XFCE + xrdp | ✅ Tested: resumable download, account, full panel click-through |
| `kali-linux` | Win-KeX | ✅ Tested: account, Win-KeX install. Needs a saved account (Win-KeX won't run as root) |
| `archlinux` | XFCE + xrdp (built from the AUR) | ✅ Tested: account, desktop install, backup/restore |
| `Ubuntu`, `Ubuntu-26.04`, `Ubuntu-22.04`, `eLxr` | XFCE + xrdp | ⚠️ Same `apt` path as Ubuntu/Debian, not tested yet |
| `FedoraLinux-*`, `openSUSE-*` | XFCE + xrdp | ⚠️ Wired up, not tested yet |
| AlmaLinux, Oracle Linux, SUSE Enterprise | — | ❌ Desktop needs extra repos (EPEL / SUSE registration). Terminal only |

"Tested" means verified on a fresh throwaway copy of that distro. The final
Remote Desktop *login* itself is still to be confirmed by hand.

---

## Configuration

By default the panel uses ``D:\Linux\WSL`` (new distros) and ``D:\Linux\Backups``
(backups), or ``WSL`` / ``WSL\Backups`` in your user folder if the PC has no D:
drive. To change that, create a ``config.json`` next to the scripts:

```json
{ "WslBase": "C:\WSL", "BackupBase": "C:\WSL\Backups", "DefaultRdpPort": 3390 }
```

Saved accounts live in an ``accounts\`` folder next to the scripts (they are
also git-ignored), so the folder is fully portable.

---|---|---|
| `WSL_BASE` | `D:\Linux\WSL` | Where new distros are installed (the panel asks each time, Enter = default) |
| `BACKUP_BASE` | `D:\Linux\Backups` | Where `[E]` saves backups and `[R]` looks for them |

If you don't have a D: drive, change both to something like `C:\WSL`. Saved
accounts always live in an `accounts\` folder next to the `.bat`, so the
folder is fully portable.

---

## Troubleshooting

| Problem | Why | What to do |
|---|---|---|
| Download fails with *"The connection with the server was reset"* | The distro's server dropped the connection (Debian's does this often) | Answer **Y** to the **resumable download**. It continues after each drop and checks the file's SHA-256 before installing |
| *"...is running its own desktop on port 3390"* | All WSL2 distros share one network, so two xrdp servers cannot use the same port | Choose **[1]** to give this distro its own free port (both desktops stay open), or **[2]** to close the other one |
| *"The Kali desktop (Win-KeX) cannot run as root"* | A freshly downloaded Kali has no normal user yet | Accounts, `[A]`, answer **Y**, then open the Desktop with that account |
| Kali: TigerVNC says *"Failed to connect to localhost:1 ... actively refused (10061)"* when opening | A minimal Kali got Win-KeX without the XFCE desktop it runs (its log says `startxfce4: not found`), so the server starts and exits at once | The current panel detects this and offers `[I]` Install, which adds `kali-desktop-xfce`. Or in a Terminal: `sudo apt install -y kali-desktop-xfce dbus-x11` |
| Kali: a TigerVNC connection error pops up when you close the distro from the panel | Older panels stopped Win-KeX as the distro's default user (often root), which cannot stop your account's desktop, so shutdown killed it under the viewer | Fixed in the current panel: it stops Win-KeX as the account that started it |
| Kali: *"Xfce Notify Daemon – Unable to start notification daemon … Wayland compositor"* appears on the Windows desktop (e.g. when logging out) | XFCE starts its notification helper through systemd, which didn't know the desktop's display, so it fell back to **WSLg** | Fixed in the current panel: it tells systemd `DISPLAY=:1` and `GDK_BACKEND=x11` when starting Win-KeX. Close the dialog; reopen the desktop through the panel |
| Desktop install ends with `AUR_BUILD_FAILED` (Arch) | Building xrdp from the AUR failed | Open a Terminal to read the error above it. Usually no internet, or a full disk |
| Remote Desktop is black **and XFCE's panel/dock appears on the Windows desktop** | WSL links **WSLg** (its bridge that shows Linux windows on Windows) into every user's runtime folder, and XFCE's toolkit prefers it over xrdp's screen | Fixed in the current panel: the session files force X11. For a desktop set up with an older panel, re-add the account with Accounts, `[A]`, **Y** (this rewrites the session files), log out of the old session, and open the Desktop again |
| Remote Desktop window is black (nothing on the Windows desktop either) | The XFCE session didn't start for that user | Log in with a user made through `[A]` → **Y** (it sets up the XFCE session). Otherwise open a Terminal and check that `~/.xsession` and `~/.xinitrc` end with `exec startxfce4` |
| Desktop closes a few seconds after opening | WSL idle shutdown | Open it through the panel. Its keep-alive holds WSL up while XFCE runs |
| WSL itself won't start | Outdated or broken WSL | `[U]` Update / repair WSL, then restart Windows |

---

## Privacy & safety

- Saved passwords are DPAPI-encrypted and only decryptable by *your* Windows
  user account on *your* machine. When an account is created, the password is
  sent to Linux over a pipe, never written to disk or put on a command line.
- This repo's `.gitignore` excludes the `accounts\` folder, so your encrypted
  logins are never committed, even if you run the panel from inside the repo.
- The setup step only turns WSL on and installs it; it does not delete your
  files. Deleting a distro requires typing its name to confirm, and Restore
  refuses to overwrite a distro that already exists.
- The resumable download only installs a file whose SHA-256 matches
  Microsoft's official WSL distro list.

---

## How it works (for the curious)

- **Three parts.** ``WSL-Control-Panel.bat`` only starts PowerShell. All the logic
  is in ``WSL-Control-Panel.ps1``. The Linux-side scripts are ordinary readable
  files in ``scripts\`` (``install-desktop.sh``, ``create-user.sh``,
  ``keepalive.sh``); the panel sends them into the distro as **base64** so no
  layer of Windows/bash quoting can mangle them.
- **Safe quoting.** The panel never builds one long command string. It passes each
  argument separately and quotes it the way Windows expects, and it validates
  Linux usernames (``^[a-z_][a-z0-9_-]*$``) before using them.
- **``wsl -e``** runs a Linux program directly, without an extra shell.
- **Passwords** go to ``chpasswd`` over stdin, never on a command line or disk.
- **Negative exit codes:** WSL reports its own errors as negative numbers, so
  the panel compares the exit code with 0.
- **stdin closed:** background ``wsl`` calls get no keyboard input, so they can
  never swallow the next thing you type.
- **``WSL_UTF8=1``** makes ``wsl.exe`` print UTF-8 so its output can be read.
- **Arch Linux:** ``xrdp`` and ``xorgxrdp`` are built from the AUR by a temporary
  non-root user (removed afterwards, along with the build-only tools and the
  ``-debug`` packages makepkg creates). The installer also sets up pacman's
  signing keys, which a brand-new Arch doesn't have yet.
- **X11, not WSLg:** the desktop session files unset ``WAYLAND_DISPLAY`` and set
  ``GDK_BACKEND=x11``, so XFCE draws inside Remote Desktop instead of on the
  Windows desktop through WSLg. They also point sound at WSLg's PulseAudio server.
- **Polkit rule:** the installer adds a rule that stops the repeating
  "Authentication is required to create a color managed device" pop-ups.
- Keep ``WSL-Control-Panel.ps1`` plain ASCII and the ``.bat`` with CRLF line
  endings; ``syntax-check.ps1`` parses the script with the PowerShell you run it
  in (use Windows PowerShell 5.1, ``powershell.exe``, which is what the launcher uses).

---

## Notes / limitations

- Desktops are XFCE-based: Kali via Win-KeX, every other distro via xrdp.
- Compacting a disk needs administrator rights and stops all of WSL.
