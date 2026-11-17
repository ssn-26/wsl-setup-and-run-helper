# Changelog

What changed in each version, for people using WSL Control Panel. When a
version tag is pushed, its section here becomes the notes of the GitHub
release (see `.github/workflows/release.yml`), so write the section before
tagging. Headings are `## <version>`, exactly as in `PANEL_VERSION`.

## 2.5.0

- **App store.** Browse Linux apps from Flathub by category or search, with
  icons, screenshots, descriptions and download sizes, and install one into any
  distro in one click. Apps open as normal Windows windows (WSLg).
- **Choose your desktop.** XFCE, KDE Plasma, Cinnamon, MATE or LXQt, each shown
  with a sketch of its layout, how much it looks like Windows or macOS, how
  customisable and light it is, and its rough size. Switch later with
  **Choose desktop** on the distro page.
- **Clone a distro.** A full copy under a new name, with nothing downloaded
  again. It keeps the login and saved accounts and gets its own Remote Desktop
  port.
- **Portable copy.** Every release also has `WSL-Control-Panel-Portable.zip`:
  unzip it anywhere and run, nothing is installed.
- **Safer updates.** Each release lists the SHA-256 fingerprints of its files
  (`WSL-Control-Panel-SHA256SUMS.txt`), and **Update now** installs a download
  only if it matches.
- The desktop shortcut is now a choice in the Setup (on by default).
- **Smaller desktops.** On Debian and Ubuntu a desktop no longer pulls in
  printer tools, screensavers and other extras: XFCE or LXQt is about 500 MB
  instead of up to 1.7 GB. LXQt's "Power Management crashed" popup is gone,
  and so are the "shortcut cannot be registered" popups at login.
- **Right time.** The Linux clock follows your Windows time zone.
- **Tidy Start menu.** A desktop's own apps are kept out of the Windows Start
  menu (they stay in the Linux menu); a switch on the distro page shows them.
- **Choose desktop** shows which desktops are installed and which one is in
  use, and switches to an installed one in seconds.
- Long downloads show how many MB have arrived. Folder pickers are the normal
  Windows ones and open where you were last time; Back up remembers .tar or
  .vhdx. Removing a saved login asks first.
- Two distros' desktops can be open at the same time again (they no longer
  fight over the same display number).
- Fixed: a backup right after using a distro ("file in use"), the size of a
  distro restored from .vhdx, a second copy of a distro under a new name,
  empty folders after a failed download, and Terminal starting in the app's
  folder.
- Fixed: a silent Setup install into a chosen folder (`/DIR=`) stopped with
  "You must enter a full path".
- Tidier folders: the app's files are now in one `app` folder (`app\windows`
  and `app\linux`). Updating moves an existing install over by itself; your
  logins and settings stay. `WSL-Control-Panel.bat` is gone: install the app,
  or use the portable zip.
- Messages that pop up while a tool is open now show on top of it instead of
  behind it.

## 2.4.0

- You choose where the app is installed: the Setup's folder box starts empty,
  and the PowerShell install asks with a folder window. Updates keep that
  folder.
- Uninstalling a PowerShell install now finds the app wherever it was
  installed.

## 2.3.1

- Tools open across the whole window instead of in a small box.
- Scroll bars follow the dark and light theme.

## 2.3.0

- A Setup wizard (`WSL-Control-Panel-Setup.exe`) and one-click updates from
  inside the app.

## 2.2.1

- Downloads contain only what the app needs.

## 2.2.0

- An installable app with no console window, and a second round of design.

## 2.1.0

- A native Windows 11 look.

## 2.0.0

- The panel becomes a window.
