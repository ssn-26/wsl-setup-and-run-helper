# WSL Setup and Run Helper

A single Windows batch file that gives new users a **no-code, menu-driven way to
install and run Linux on Windows** through WSL (Windows Subsystem for Linux).

Double-click it on a brand-new PC and it installs WSL for you. On a PC that
already has WSL it becomes a control panel for your Linux distros: download,
open (desktop or terminal), back up, restore, close and delete them from one
menu.

No PowerShell knowledge, no memorized `wsl` commands.

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
| *Enter* | Quick-open | Wakes the first distro and opens its desktop with its first saved account |
| number | Manage a distro | Open (Desktop / Terminal), Close, or Delete it |
| `C` | Close a running distro | `wsl --terminate`, which frees its RAM |
| `S` | Shut down all WSL | `wsl --shutdown`, which frees the whole WSL VM |
| `N` | Download a new distro | `wsl --install` from Microsoft's official list, with a resumable fallback |
| `E` | Back up a distro | `wsl --export` saves everything to one `.tar` file |
| `R` | Restore a backup | `wsl --import` brings a backup back, on this PC or a new one |
| `U` | Update / repair WSL | `wsl --update` (admin) |
| `Q` | Quit | Closes the panel; distros keep running |

- **Desktop or Terminal.** Kali opens in its own Win-KeX window. Every other
  distro opens in Windows Remote Desktop (xrdp on port **3390**, so it never
  clashes with Windows' own Remote Desktop on 3389).
- **One-click desktop install.** If a distro has no desktop yet, the panel
  installs XFCE + xrdp for you. It auto-detects the package manager (apt / dnf
  / zypper / yum / pacman), and on Arch it builds xrdp from the AUR.
- **Saved accounts.** Store a Linux username + password per distro so the
  panel logs you in automatically. Passwords are **encrypted with Windows
  DPAPI**, never stored as plain text. On a fresh distro, adding an account
  also **creates that Linux user** with admin rights (`sudo` or `wheel`) and an
  XFCE session, so the first login just works.
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

1. Copy this folder anywhere and double-click **`WSL-Control-Panel.bat`**.
   On a PC without WSL, allow the administrator prompt and restart if asked.
2. **`[N]` Download**: type a name from the list (e.g. `Ubuntu-24.04`,
   `Debian`, `archlinux`, `kali-linux`) and press Enter for the default folder.
3. **Create your login**: pick the distro by number, then **`[O]` Open**,
   **`[A]` Add an account**, and answer **Y**. Choose a username and password.
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
   locked to the old Windows login. Re-add yours with Open, `[A]`, and answer
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

Two lines near the top of `WSL-Control-Panel.bat`:

| Setting | Default | Used for |
|---|---|---|
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
| *"...is running its own desktop on port 3390"* | All WSL2 distros share one network, and only one xrdp can use port 3390 | Answer **Y** to close the other distro, or close it with `[C]` first |
| *"The Kali desktop (Win-KeX) cannot run as root"* | A freshly downloaded Kali has no normal user yet | Open, `[A]`, answer **Y**, then open the Desktop with that account |
| Desktop install ends with `AUR_BUILD_FAILED` (Arch) | Building xrdp from the AUR failed | Open a Terminal to read the error above it. Usually no internet, or a full disk |
| Remote Desktop window is black | The XFCE session didn't start for that user | Log in with a user made through `[A]` → **Y** (it sets up the XFCE session). Otherwise open a Terminal and check that `~/.xsession` and `~/.xinitrc` contain `exec startxfce4` |
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

- **The Linux-side scripts** (the desktop installer and the account creator) are
  stored inside the `.bat` as **base64** text and decoded inside Linux. That
  way no layer of cmd/PowerShell/bash quoting can mangle them. The desktop
  installer is written to a temp file in short lines, because cmd silently
  drops any command longer than 8,191 characters.
- **`wsl -e`** runs a Linux program directly, without an extra shell. The
  account creator uses it so the username isn't expanded (and lost) by a shell
  in between.
- **Negative exit codes:** WSL reports its own errors as negative numbers, so
  the panel compares the exit code with 0 instead of using `if errorlevel 1`.
- **`<nul`** after `wsl` commands stops them from reading the keyboard, so they
  can never swallow the next thing you type.
- **Arch Linux:** `xrdp` and `xorgxrdp` are built from the AUR by a temporary
  non-root user (removed afterwards). The installer also sets up pacman's
  signing keys, which a brand-new Arch doesn't have yet.

---

## Notes / limitations

- Desktops are XFCE-based: Kali via Win-KeX, every other distro via xrdp on
  port 3390.
- Only one xrdp desktop can run at a time, because WSL2 distros share one
  network and port.
- Paths and ports reflect a personal setup. Adjust `WSL_BASE`, `BACKUP_BASE`
  and the port to taste.
