# WSL Setup and Run Helper

A small Windows app that gives new users a **no-code way to install and run
Linux on Windows** through WSL (Windows Subsystem for Linux), in a proper
Windows 11-style window with buttons.

## Install

### [⬇ Download for Windows](https://github.com/ssn-26/wsl-setup-and-run-helper/releases/latest/download/WSL-Control-Panel-Setup.exe)

1. Open the downloaded **WSL-Control-Panel-Setup.exe**.
2. Click **Next**, then **Browse** to choose where to put the app (there is no
   default folder - you pick it), then **Install** and **Finish**.
3. WSL Control Panel opens. Later, open it from the Start menu or the desktop.

No administrator rights needed. Windows 10 and 11.

> **If Windows shows "Windows protected your PC"**, click **More info**, then
> **Run anyway**. This appears because the Setup is not signed with a paid
> certificate yet - it is the same app as the code in this repository. You only
> see it once: updates are installed from inside the app, without the warning.

**Updates:** when a new version is out, the app shows **Update now**. One click,
and it updates itself; your distros, logins and settings stay as they are.

**Uninstall:** Settings -> Apps -> WSL Control Panel. It asks whether to delete
your saved logins too; your Linux distros and backups are never touched.

<details><summary>Advanced: install with PowerShell instead (no warning at all)</summary>

Open **PowerShell**, paste this line and press Enter:

```powershell
irm https://raw.githubusercontent.com/ssn-26/wsl-setup-and-run-helper/main/install.ps1 | iex
```

It installs the same app (building its small exe on your PC). The first time,
a folder window asks where to put it. Run the line again to update; it keeps
the folder you chose.
</details>

Double-click it on a brand-new PC and it installs WSL for you. On a PC that
already has WSL it becomes a control panel for your Linux distros: download,
open (desktop or terminal), back up, restore, close and delete them from one
window, in a dark or light theme.

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

- **Left side:** your distros (running ones have a green dot), **Open default
  desktop**, **Download a distro**, the **App store**, and the tools: Back up,
  Restore, Close running, Shut down all, Compact a disk, Memory / CPU, Storage
  locations, Update WSL.
- **Right side:** the distro you picked - **Open desktop**, **Terminal** and
  **Close**, "Open as" (which saved login to use), its desktop style and apps,
  its saved accounts, Compact disk, **Clone**, its Remote Desktop port, systemd
  on/off, and Delete.

| Button | What happens behind the scenes |
|---|---|
| Open desktop | Wakes the distro and opens its desktop (Remote Desktop, or Win-KeX on Kali), logged in with the chosen saved account |
| Terminal | A terminal window (Windows Terminal when installed) as the chosen account |
| Close / Close running | `wsl --terminate`, which frees that distro's RAM |
| Shut down all | `wsl --shutdown`, which frees the whole WSL VM |
| Download a distro | `wsl --install` from Microsoft's official list, with a resumable fallback |
| Back up | `wsl --export` saves everything to one `.tar` (or faster `.vhdx`) file |
| Restore | `wsl --import` brings a backup back, on this PC or a new one |
| Clone | `wsl --export --vhd` straight into the new folder, then `wsl --import-in-place`: a full copy under a new name, with nothing downloaded again |
| Choose desktop | Installs XFCE, KDE Plasma, Cinnamon, MATE or LXQt (+ xrdp) and makes Remote Desktop start it |
| App store | Installs Linux apps from [Flathub](https://flathub.org) with `flatpak install`; they open as normal Windows windows through WSLg |
| Compact | Hands unused `ext4.vhdx` space back to Windows (admin, via diskpart) |
| Memory / CPU | Sets `memory`, `processors` and `swap` in `.wslconfig`; your other settings stay (a copy is kept as `.wslconfig.bak`) |
| Storage locations | Shows where every distro, your backups and the panel's settings are, each with an **Open** button |
| Update WSL | `wsl --update` (admin) |

Long jobs (downloads, desktop installs, backups) show their live output in a
progress window, so you can see what is happening, and the panel never freezes.

The distro page shows its disk size (and the free space on that drive) and the
memory WSL is using right now, refreshed every few seconds. Keyboard: **Esc**
closes a dialog, **Enter** presses its main button, **F5** refreshes, and
**Ctrl+1** to **Ctrl+9** pick a distro.

- **Desktop or Terminal.** Kali opens in its own Win-KeX window. Every other
  distro opens in Windows Remote Desktop (xrdp, default port **3390** so it never
  clashes with Windows' own Remote Desktop on 3389). Each distro can have its own
  port, so two desktops can be open at once.
- **Pick your desktop.** If a distro has no desktop yet, the panel shows a
  card for each desktop it can install - XFCE, KDE Plasma, Cinnamon, MATE and
  LXQt - with a sketch of its layout, how much it looks like Windows or macOS,
  how customisable and how light it is, and its rough download size. It
  installs your choice + xrdp, auto-detecting the package manager (apt / dnf /
  zypper / yum / pacman; on Arch it builds xrdp from the AUR). **Choose
  desktop** on the distro page switches to another one later. (Kali keeps its
  own XFCE through Win-KeX. Fedora's KDE has no X11 session for Remote Desktop
  any more, so the panel says so and lets you pick another.)
- **App store.** Browse Flathub's apps by category or search, with icons,
  screenshots, descriptions and download sizes, and install one into any
  distro with one click. The panel sets Flatpak up the first time (the first
  app also downloads a shared runtime, often 300-900 MB, that later apps
  reuse). Installed apps open as normal windows on your Windows desktop
  (WSLg) and are linked into the distro's menu so WSLg can add them to the
  Windows Start menu. Uninstall removes runtimes no app needs any more.
- **Clone a distro.** A full copy under a new name: programs, desktop, users,
  files, the same default login and the saved logins. The copy gets its own
  Remote Desktop port, so both desktops can be open at once. Handy before
  trying something risky, or to set one distro up and copy it.
- **Saved accounts.** Store a Linux username + password per distro so the
  panel logs you in automatically. Passwords are **encrypted with Windows
  DPAPI**, never stored as plain text. On a fresh distro, adding an account
  also **creates that Linux user** with admin rights (`sudo` or `wheel`) and a
  desktop session, so the first login just works. You can also change a password or
  remove a saved account. If a saved account's Linux user no longer exists (for
  example the distro was re-downloaded), the panel offers to create it again.
- **Backup & restore.** A backup holds *everything* inside the distro:
  programs, the desktop setup, users and files. Restoring it on a new laptop
  means no setting up again.
- **Keep-alive.** WSL normally shuts an idle distro down seconds after the
  launcher closes. The panel keeps it running while the desktop is in use.
- **Docker / Rancher Desktop distros are left alone.** `docker-desktop` and
  `rancher-desktop` (and their `-data` disks) are hidden from the menus, but
  the panel still sees them running, so it never shuts WSL down under them.
- **Easy to read.** Each colour means one thing: blue for the main action,
  green for running / done, yellow for warnings, red for errors and anything
  that deletes, grey for explanations. Quick results pop up in the corner. The
  theme follows Windows' light / dark setting; the button at the bottom left
  switches it.
- **Everything explains itself.** Each dialog says what it will do and which
  `wsl` command runs, so you learn the tool as you use it.

---

## Requirements

- Windows 10 (2004+) or Windows 11.
- Administrator access for the **one-time** WSL install/update (Windows shows a
  UAC prompt; the panel itself runs as a normal window).
- An internet connection to download WSL, distros and desktop packages.

**Why there is no security warning.** Windows tags everything a browser
downloads as "from the internet", and that tag is what triggers *"Do you want to
run this file?"* and SmartScreen. Signed apps avoid it with a paid certificate;
this one avoids it by being downloaded by PowerShell itself (no tag) and by
building its small `WSL Control Panel.exe` on your PC with the C# compiler that
is part of Windows. The exe only starts the panel's PowerShell scripts inside
itself, so there is no console window behind the app.

---

## Quick start: your first Linux desktop

1. [Install it](#install) and open **WSL Control Panel** from the Start menu.
   On a PC without WSL, allow the administrator prompt and restart if asked.
2. **Download a distro**: pick one from the list (e.g. Ubuntu 24.04, Debian,
   Arch Linux, Kali Linux) and **choose the folder** to store it in (e.g. on a drive with plenty of space).
3. **Create your login** right away: when the download finishes, the panel
   asks you to create your Linux user. Choose a username (it suggests your
   Windows name) and a password. The progress window shows each step while it
   creates the account (on Arch, installing `sudo` takes a minute or two).
   Skipped it? The panel asks again the first time you open the desktop.
4. **Open desktop**: the first time, the panel says there's no desktop yet.
   Press **Install the desktop now**. This takes 5-20 minutes (Arch is the
   slowest, because it compiles xrdp). Remote Desktop then opens and logs you in.
5. **Back up** once it's set up the way you like.

## Moving to a new PC

1. On the old PC: **Back up** the distro, then copy the `.tar` file (from
   the folder you chose for it) to a USB drive or cloud storage.
2. On the new PC: run the panel (it installs WSL if needed), then **Restore**.
   Pick the backup (or **Browse** for it). The distro comes back exactly as it
   was, with your normal user as the default login.
3. Saved panel accounts are **not** in the backup, because their passwords are
   locked to the old Windows login. Re-add yours with **Add an account**, with
   *"Also create this user inside the distro"* switched **off** (the Linux user
   already exists inside the backup).

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

## Folder layout

Installed, only what the app needs goes on your PC, in the folder you chose
when installing (there is no default; updates keep that folder):

```
WSL Control Panel.exe     <- the app
unins000.exe / .dat       the uninstaller (with the PowerShell install: install.ps1 instead)
bash\                     the Linux-side scripts (install-desktop.sh, create-user.sh, keepalive.sh,
                          flatpak.sh for the App store)
                          + xsession, the desktop session file both installers write
powershell\               the panel: WSL-Control-Panel.ps1 (the window), Engine.ps1 (everything
                          it does), AppIcon.ps1 (the icon), ui\MainWindow.xaml (layout and colours)
data\                     the panel's own files (never committed to git)
  config\                 config.json + accounts\ (saved logins, passwords DPAPI-encrypted)
  logs\                   the full output of each desktop install
```

The repository also has `launcher\` (the exe's source and `build.ps1`),
`installer\` (the Setup wizard, `setup.iss`, built by GitHub for every release
with Inno Setup), `install.ps1` (the PowerShell install), and `Install.bat` /
`WSL-Control-Panel.bat` (for an unzipped copy). This README, the licence, the
installer and the git/CI files stay on GitHub: they are left out of "Download
ZIP" too (`export-ignore` in `.gitattributes`).

**Your Linux disks and backups are never stored in the panel's folder.**
Download, Back up and Restore always ask where to save (the folder picker
opens where you chose last time), so they go where you decide - for example a
drive with plenty of space - and updating or uninstalling the panel never
touches them. Each distro's page shows where its disk is (**Open folder**), and
**Storage locations** lists all of them, your last backup folder and the
settings folder. Uninstalling only offers to delete the saved logins and
settings.

---

## Troubleshooting

| Problem | Why | What to do |
|---|---|---|
| Download fails with *"The connection with the server was reset"* | The distro's server dropped the connection (Debian's does this often) | Choose **Try the resumable download**. It continues after each drop and checks the file's SHA-256 before installing |
| *"...is running its own desktop on port 3390"* | All WSL2 distros share one network, so two xrdp servers cannot use the same port | Choose **Give it a different port** (both desktops stay open), or **Close** the other one |
| *"The Kali desktop (Win-KeX) cannot run as root"* | A freshly downloaded Kali has no normal user yet, and the offer to create one was skipped | Choose **Create my user** (or open the desktop again and create it when asked) |
| Kali: TigerVNC says *"Failed to connect to localhost:1 ... actively refused (10061)"* when opening | A minimal Kali got Win-KeX without the XFCE desktop it runs (its log says `startxfce4: not found`), so the server starts and exits at once | The panel detects this and offers **Install the desktop now**, which adds `kali-desktop-xfce`. Or in a Terminal: `sudo apt install -y kali-desktop-xfce dbus-x11` |
| Kali: a TigerVNC connection error pops up when you close the distro from the panel | Older panels stopped Win-KeX as the distro's default user (often root), which cannot stop your account's desktop, so shutdown killed it under the viewer | Fixed in the current panel: it stops Win-KeX as the account that started it |
| Kali: *"Xfce Notify Daemon – Unable to start notification daemon … Wayland compositor"* appears on the Windows desktop (e.g. when logging out) | XFCE starts its notification helper through systemd, which didn't know the desktop's display, so it fell back to **WSLg** | Fixed in the current panel: it tells systemd `DISPLAY=:1` and `GDK_BACKEND=x11` when starting Win-KeX. Close the dialog; reopen the desktop through the panel |
| Desktop install ends with `AUR_BUILD_FAILED` (Arch) | Building xrdp from the AUR failed | Read the error in the install log the panel names (in `data\logs`). Usually no internet, or a full disk |
| Remote Desktop is black **and XFCE's panel/dock appears on the Windows desktop** | WSL links **WSLg** (its bridge that shows Linux windows on Windows) into every user's runtime folder, and XFCE's toolkit prefers it over xrdp's screen | Fixed in the current panel: the session files force X11. For a desktop set up with an older panel, re-add the account with **Add an account** (creating the user; this rewrites the session files), log out of the old session, and open the Desktop again |
| Remote Desktop window is black (nothing on the Windows desktop either) | The desktop session didn't start for that user | Log in with a user the panel created (it sets up the session). Otherwise open a Terminal and check that `~/.xsession` and `~/.xinitrc` end with `exec "$SESSION"`, and that `/etc/wsl-panel-session` names the desktop's start command (e.g. `startplasma-x11`) |
| After **Choose desktop**, Remote Desktop still shows the old desktop | The old desktop session is still logged in; closing the Remote Desktop window keeps it running | Log out from inside the desktop (its menu: Log out / Sign out), then press **Open desktop** again |
| An App store app doesn't open, or isn't in the Start menu | WSLg isn't available (Windows 10 without WSLg, or an old WSL), or the Start menu hasn't refreshed yet | Run **Update WSL**, then **Shut down WSL** and try again. The app can always be started with **Open** in the App store |
| Desktop closes a few seconds after opening | WSL idle shutdown | Open it through the panel. Its keep-alive holds WSL up while XFCE runs |
| *"Failed to attach disk ... ext4.vhdx ... ERROR_SHARING_VIOLATION"* | Another program has the distro's disk file open: a stuck WSL, a copy or backup of `data\linux` still running, the `.vhdx` double-clicked (Windows mounted it), or antivirus | The panel catches this before opening and offers **Shut down WSL and try again**, or **Detach the disk and try again**. Still stuck? Restart Windows |
| *"Do you want to run this file?"* every time | Windows marks files from a downloaded ZIP | [Install it](#install) with the one line instead. Or click **Run** once (the panel then unblocks its own files), or unblock the ZIP before extracting |
| A console window stays open behind the panel | Started with `WSL-Control-Panel.bat`: on Windows 11 the console opens in Windows Terminal, which ignores "hidden" | [Install it](#install) and use **WSL Control Panel** from the Start menu (no console at all) |
| The installer says *"Building WSL Control Panel.exe failed"* | Rare: antivirus blocked the C# compiler, or .NET Framework 4 is damaged | Allow it in your antivirus and run the line again, or use `WSL-Control-Panel.bat` from the install folder |
| WSL itself won't start | Outdated or broken WSL | **Update WSL**, then restart Windows |

---

## Privacy & safety

- Saved passwords are DPAPI-encrypted and only decryptable by *your* Windows
  user account on *your* machine. When an account is created, the password is
  sent to Linux over a pipe, never written to disk or put on a command line.
- This repo's `.gitignore` excludes the whole `data\` folder, so your encrypted
  logins (and your Linux disks and backups) are never committed, even if you run
  the panel from inside the repo.
- The setup step only turns WSL on and installs it; it does not delete your
  files. Deleting a distro requires typing its name to confirm, and Restore
  refuses to overwrite a distro that already exists.
- The resumable download only installs a file whose SHA-256 matches
  Microsoft's official WSL distro list.
- The steps that need administrator rights (first-time setup, disk compaction)
  are passed straight to the elevated window, never through a script file in
  `%TEMP%` that another program could change first.
- Changing the xrdp port refuses 3389 (Windows' own Remote Desktop), a port
  another distro is set to, and a port something on Windows already listens on.

---

## How it works (for the curious)

- **The parts.** `WSL-Control-Panel.bat` only starts PowerShell, with no console
  window. `powershell\Engine.ps1` does all the work and never asks anything:
  each step returns a result, and the window (`powershell\WSL-Control-Panel.ps1`
  + `ui\MainWindow.xaml`, a WPF window) decides what to ask next. Long jobs run
  in a background PowerShell runspace that loads the same engine and streams its
  output back, so the window never freezes. The Linux-side scripts are ordinary
  readable files in `bash\` (`install-desktop.sh`, `create-user.sh`,
  `keepalive.sh`); the panel sends them into the distro as **base64** so no
  layer of Windows/bash quoting can mangle them.
- **Safe quoting.** The panel never builds one long command string. It passes each
  argument separately and quotes it the way Windows expects, and it validates
  Linux usernames (`^[a-z_][a-z0-9_-]*$`) before using them.
- **Any Windows language.** The distro list is read from the registry plus
  `wsl --list --running --quiet` (bare names), not from `wsl -l -v`, whose
  table is translated on non-English Windows.
- **Kali is detected from `/etc/os-release`**, so a Kali restored under another
  name still opens with Win-KeX.
- **Accounts on any distro.** Creating an account installs `sudo` if the distro
  lacks it and creates a `wheel` group if there is no admin group at all.
- **`wsl -e`** runs a Linux program directly, without an extra shell.
- **Passwords** go to `chpasswd` over stdin, never on a command line or disk.
- **Negative exit codes:** WSL reports its own errors as negative numbers, so
  the panel compares the exit code with 0.
- **stdin closed:** background `wsl` calls get no keyboard input, so they can
  never hang waiting for one.
- **`WSL_UTF8=1`** makes `wsl.exe` print UTF-8 so its output can be read.
- **Arch Linux:** `xrdp` and `xorgxrdp` are built from the AUR by a temporary
  non-root user (removed afterwards, along with the build-only tools and the
  `-debug` packages makepkg creates). The installer also sets up pacman's
  signing keys, which a brand-new Arch doesn't have yet.
- **X11, not WSLg:** the desktop session files unset `WAYLAND_DISPLAY` and set
  `GDK_BACKEND=x11`, so XFCE draws inside Remote Desktop instead of on the
  Windows desktop through WSLg. They also point sound at WSLg's PulseAudio server.
- **Polkit rule:** the installer adds a rule that stops the repeating
  "Authentication is required to create a color managed device" pop-ups.
- Keep the `.ps1` files plain ASCII and the `.bat` with CRLF line endings.
  Check the scripts parse with Windows PowerShell 5.1 (`powershell.exe`, which
  is what the launcher uses), not PowerShell 7, which accepts syntax 5.1 rejects.
- **Checks on GitHub.** Every push runs `.github/workflows/checks.yml`: it
  parses every `.ps1` with Windows PowerShell 5.1, checks they are plain ASCII
  and that the `.bat` is CRLF, **builds the window** (`-Validate`) on a Windows
  machine, runs `shellcheck` on `bash\`, and lists PSScriptAnalyzer's findings
  (report only).
- **Version.** The window shows its version (`$PANEL_VERSION` at the top of
  `WSL-Control-Panel.ps1`). Raise it when you share a change, so a bug report
  can say which version it came from.

---

## Notes / limitations

- Kali opens its own XFCE via Win-KeX; every other distro opens the desktop you
  chose (XFCE unless you picked another) via xrdp. Only XFCE has been tested
  on every distro so far; the other desktops are wired up for apt, dnf, zypper
  and pacman and were checked on Ubuntu 24.04 (packages and session commands).
- The App store needs WSLg (Windows 11, or Windows 10 with the Store version of
  WSL) to show apps as windows. Apps are Flatpaks from Flathub, installed
  system-wide in the distro.
- Compacting a disk needs administrator rights and stops all of WSL.

---

## Licence

MIT. See [LICENSE](LICENSE). You may use, change and share this project,
including commercially, as long as the copyright notice stays with it. It comes
with no warranty.
