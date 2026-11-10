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
