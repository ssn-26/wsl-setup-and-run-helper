# WSL Setup and Run Helper

A single Windows batch file that gives new users a **no-code, menu-driven way to
install and run Linux on Windows** through WSL (Windows Subsystem for Linux).

Double-click it on a brand-new PC and it will install WSL for you; run it on a
PC that already has WSL and it becomes a control panel for your Linux distros —
download, open (desktop or terminal), close, and delete them from one menu.

No PowerShell knowledge, no memorized `wsl` commands.

---

## What it does

**First run on a fresh PC — it bootstraps WSL itself:**
1. Detects that WSL isn't set up yet.
2. Asks once, then (via a Windows administrator/UAC prompt) turns on the
   required Windows features, installs the WSL platform, and updates it.
3. Tells you if a **restart** is needed. After restarting, run it again and
   download your first Linux distro from the menu.

**Everyday use — a control panel for your distros:**
- **List** all installed distros and whether they're running.
- **Open** a distro as a **Desktop** (visual) or a **Terminal**.
  - Ubuntu-style desktops open over Remote Desktop (xrdp).
  - Kali opens via its own Win-KeX window.
  - Includes a keep-alive so the desktop doesn't close seconds after launch.
- **Save accounts** per distro so you don't retype your login. Passwords are
  stored **encrypted with Windows DPAPI** (tied to your Windows login) — never
  in plain text — in an `accounts\` folder next to the file.
- **Close** one/all running distros, or **Shut down all WSL** to free memory.
- **Download** a new distro from Microsoft's official online list.
- **Update / repair WSL** itself.
- **Delete** a distro (with type-the-name-to-confirm protection).

---

## Requirements

- Windows 10 (2004+) or Windows 11.
- Administrator access for the **one-time** WSL install/update (Windows shows a
  UAC prompt; the panel itself runs as a normal window).
- An internet connection to download WSL and any distros.

---

## How to use

1. Copy this folder anywhere on your PC.
2. Double-click **`WSL-Control-Panel.bat`**.
3. Follow the on-screen menu.

On first run with no WSL, allow the administrator prompt and restart if asked.

---

## Configuration

When you download a distro, the panel asks where to install it — press
Enter to accept the default (`D:\Linux\WSL`), or type any folder. To change
that default, edit the `WSL_BASE` line near the top of `WSL-Control-Panel.bat`.

---

## Privacy & safety

- **No account info is included in this repo.** Saved logins live in an
  `accounts\` folder created at runtime and are excluded via `.gitignore`.
- Saved passwords are DPAPI-encrypted and only decryptable by *your* Windows
  user account on *your* machine.
- The setup step only turns WSL on and installs it — it does not delete your
  files. Deleting a distro is the only destructive action and requires you to
  type the distro's name to confirm.

---

## Notes / limitations

- Desktop launching is tuned for XFCE-based desktops (Ubuntu via xrdp on port
  3390, Kali via Win-KeX). A freshly downloaded distro has no desktop until you
  install one — open it as a **Terminal** first.
- Paths and ports reflect a personal setup; adjust to taste.
