#!/bin/bash
# ==============================================================================
# install-desktop.sh
# Auto-installs a desktop + xrdp on any major Linux distribution under WSL.
# Desktops: xfce (default), kde (KDE Plasma), cinnamon, mate, lxqt.
# Configures xrdp to listen on specified port (default: 3390).
# Records the chosen desktop in /etc/wsl-panel-session, which the session file
# (app/linux/xsession) reads, so Remote Desktop starts that desktop.
# Configures Polkit to suppress annoying authentication prompts (colord/packagekit).
# Configures WSLg PulseAudio forwarding for sound support.
#
# Usage: ./install-desktop.sh [PORT] [DESKTOP]
# Example: ./install-desktop.sh 3390 kde
# Exit codes: 21 unknown package manager, 22 unknown desktop, 23 that desktop
# is not available for this distro, 20 AUR build failed (Arch).
# ==============================================================================

PORT="${1:-3390}"
DESKTOP="${2:-xfce}"

# The command that starts each desktop in an X11 session (xrdp has no Wayland).
case "$DESKTOP" in
    xfce)     SESSION=startxfce4 ;;
    kde)      SESSION=startplasma-x11 ;;
    cinnamon) SESSION=cinnamon-session ;;
    mate)     SESSION=mate-session ;;
    lxqt)     SESSION=startlxqt ;;
    *) echo "UNKNOWN_DESKTOP: $DESKTOP"; exit 22 ;;
esac
echo "==> Starting desktop installation: $DESKTOP (Target Port: $PORT)..."

not_available() {
    echo "DESKTOP_NOT_AVAILABLE: the $DESKTOP desktop is not available for this distro. Pick another one."
    exit 23
}

# Tries each package list in turn until one installs (names differ between
# releases). $1 is the install command, the rest are quoted package lists.
try_lists() {
    cmd="$1"; shift
    for list in "$@"; do
        # shellcheck disable=SC2086
        $cmd $list && return 0
        echo "==> '$list' did not install - trying the next name..."
    done
    return 1
}

# 1. Package manager installers
# Without "Recommends" a desktop is 3-4 times smaller (LXQt on Debian 13:
# 458 MB instead of 1.7 GB): no printer tools, screensavers, boot splash or
# power manager (which only crashes in WSL). What a desktop does need from its
# Recommends is named here: xorgxrdp (Remote Desktop's X server), the window
# manager of KDE (kwin-x11) and LXQt (openbox), a terminal, an editor, icons.
install_apt() {
    export DEBIAN_FRONTEND=noninteractive
    APT="apt-get install -y --no-install-recommends"
    apt-get update
    $APT xrdp xorgxrdp dbus-x11 xauth x11-xserver-utils tzdata
    case "$DESKTOP" in
        xfce)     try_lists "$APT" "xfce4 xfce4-terminal mousepad xfce4-notifyd tango-icon-theme xfce4-whiskermenu-plugin xfce4-taskmanager xfce4-screenshooter" \
                                   "xfce4 xfce4-terminal mousepad" ;;
        kde)      try_lists "$APT" "kde-plasma-desktop kwin-x11 konsole kwrite" "plasma-desktop kwin-x11 konsole" ;;
        cinnamon) try_lists "$APT" "cinnamon-core gnome-themes-extra" "cinnamon-core" "cinnamon" ;;
        mate)     try_lists "$APT" "mate-desktop-environment-core" "mate-desktop-environment" ;;
        # LXQt brings no window manager of its own (openbox is only "recommended"),
        # and its icons (Papirus) and wallpaper need Qt's SVG support.
        lxqt)     try_lists "$APT" "lxqt-core openbox featherpad lxqt-sudo lxqt-config lxqt-notificationd lxqt-branding-debian papirus-icon-theme qt6-svg-plugins" \
                                   "lxqt-core openbox featherpad lxqt-sudo papirus-icon-theme libqt5svg5" "lxqt-core openbox" ;;
    esac
}

install_dnf() {
    dnf install -y xrdp xorgxrdp
    case "$DESKTOP" in
        xfce) dnf group install -y "Xfce Desktop" || dnf groupinstall -y "Xfce" || dnf install -y @xfce-desktop-environment ;;
        *)    dnf install -y "@${DESKTOP}-desktop-environment" || dnf group install -y "${DESKTOP}-desktop-environment" ;;
    esac
}

install_yum() {
    [ "$DESKTOP" = xfce ] || not_available
    yum install -y epel-release || true
    yum groupinstall -y "Xfce" || true
    yum install -y xrdp
}

install_zypper() {
    zypper --non-interactive install xrdp
    case "$DESKTOP" in
        xfce)     zypper --non-interactive install -t pattern xfce ;;
        kde)      zypper --non-interactive install -t pattern kde_plasma || zypper --non-interactive install plasma6-session plasma6-session-x11 ;;
        cinnamon) zypper --non-interactive install -t pattern cinnamon || zypper --non-interactive install cinnamon ;;
        mate)     zypper --non-interactive install -t pattern mate || zypper --non-interactive install mate-session-manager ;;
        lxqt)     zypper --non-interactive install -t pattern lxqt || zypper --non-interactive install lxqt-session ;;
    esac
}

arch_keyring() {
    if ! pacman-key --list-keys 2>/dev/null | grep -q '^pub'; then
        echo "==> Initializing pacman keys (Arch first run)..."
        pacman-key --init >/dev/null 2>&1
        pacman-key --populate archlinux >/dev/null 2>&1
    fi
}

install_pacman() {
    arch_keyring
    pacman -Syu --needed --noconfirm base-devel git sudo xorg-server
    case "$DESKTOP" in
        xfce)     try_lists "pacman -S --needed --noconfirm" "xfce4" ;;
        # Plasma 6.4 moved the X11 session into its own package.
        kde)      try_lists "pacman -S --needed --noconfirm" "plasma-desktop plasma-x11-session" "plasma-desktop" ;;
        cinnamon) try_lists "pacman -S --needed --noconfirm" "cinnamon" ;;
        mate)     try_lists "pacman -S --needed --noconfirm" "mate" ;;
        lxqt)     try_lists "pacman -S --needed --noconfirm" "lxqt" ;;
    esac
    
    # Create temporary unprivileged user to build AUR packages
    id -u aurbuild >/dev/null 2>&1 || useradd -r -m -s /bin/bash aurbuild
    echo 'aurbuild ALL=(ALL) NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/99-aurbuild
    chmod 440 /etc/sudoers.d/99-aurbuild
    
    aur_ok=1
    for pkg in xrdp xorgxrdp; do
        pacman -Q "$pkg" >/dev/null 2>&1 && continue
        echo "==> Building $pkg from AUR (this takes a few minutes)..."
        sudo -u aurbuild bash -s -- "$pkg" <<'BUILD' || { aur_ok=0; break; }
set -e
cd ~ && rm -rf "$1"
git clone --depth 1 "https://aur.archlinux.org/$1.git"
cd "$1"
keys=$(. ./PKGBUILD >/dev/null 2>&1; echo "${validpgpkeys[@]}")
if [ -n "$keys" ]; then
    gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys $keys
fi
makepkg -si --noconfirm --nocheck --rmdeps
BUILD
    done
    
    # Clean up build artifacts and temporary user
    pacman -Rns --noconfirm xrdp-debug xorgxrdp-debug >/dev/null 2>&1 || true
    rm -f /etc/sudoers.d/99-aurbuild
    pkill -u aurbuild >/dev/null 2>&1 || true
    sleep 1
    userdel -r aurbuild >/dev/null 2>&1 || true
    
    if [ "$aur_ok" != 1 ]; then
        echo "AUR_BUILD_FAILED"
        exit 20
    fi
    
    # Allow any user to run Xorg
    mkdir -p /etc/X11
    echo 'allowed_users=anybody' > /etc/X11/Xwrapper.config
    systemctl enable xrdp xrdp-sesman >/dev/null 2>&1 || true
}

# Ensure UTF-8 English locale exists on Arch
if [ -f /etc/locale.gen ] && ! locale -a 2>/dev/null | grep -qi '^en_US\.utf8$'; then
    sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
    locale-gen >/dev/null 2>&1 || true
fi

# Detect package manager and install packages
set -e
if command -v apt-get >/dev/null 2>&1; then
    echo "Detected package manager: apt"; install_apt
elif command -v dnf >/dev/null 2>&1; then
    echo "Detected package manager: dnf"; install_dnf
elif command -v zypper >/dev/null 2>&1; then
    echo "Detected package manager: zypper"; install_zypper
elif command -v yum >/dev/null 2>&1; then
    echo "Detected package manager: yum"; install_yum
elif command -v pacman >/dev/null 2>&1; then
    echo "Detected package manager: pacman"; install_pacman
else
    echo "UNKNOWN_PKG_MANAGER"
    exit 21
fi
set +e

# Some distros ship a desktop without its X11 session (Fedora's KDE is
# Wayland-only): Remote Desktop could not start it, so say so.
if ! command -v "$SESSION" >/dev/null 2>&1; then
    not_available
fi
echo "$SESSION" > /etc/wsl-panel-session
chmod 644 /etc/wsl-panel-session

# LXQt asks at the first login which window manager to use when the distro has
# more than one (e.g. another desktop's): choose openbox for everyone.
if [ "$DESKTOP" = lxqt ] && command -v openbox >/dev/null 2>&1; then
    LXQT_SESSION=/etc/xdg/lxqt/session.conf
    mkdir -p /etc/xdg/lxqt
    if [ -f "$LXQT_SESSION" ] && grep -q '^window_manager=' "$LXQT_SESSION"; then
        sed -i 's/^window_manager=.*/window_manager=openbox/' "$LXQT_SESSION"
    elif [ -f "$LXQT_SESSION" ] && grep -q '^\[General\]' "$LXQT_SESSION"; then
        sed -i '/^\[General\]/a window_manager=openbox' "$LXQT_SESSION"
    else
        printf '[General]\nwindow_manager=openbox\n' >> "$LXQT_SESSION"
    fi
fi

# A login screen (display manager) has no screen to show in WSL and only fails
# at every start; Remote Desktop logs in through xrdp instead.
for dm in sddm lightdm gdm gdm3 lxdm slim; do
    systemctl disable --now "$dm" >/dev/null 2>&1 || true
done

# 2. Configure XRDp port in /etc/xrdp/xrdp.ini
if [ -f /etc/xrdp/xrdp.ini ]; then
    echo "==> Configuring xrdp to listen on port $PORT..."
    # Only the [Globals] "port=<digits>" line: the [Xorg]/[Xvnc] sections have
    # "port=-1", which must stay exactly as it is.
    sed -i -E "/^\[Globals\]/,/^\[/ s/^port=[0-9]+[[:space:]]*$/port=$PORT/" /etc/xrdp/xrdp.ini
    grep -Eq "^port=${PORT}[[:space:]]*$" /etc/xrdp/xrdp.ini || sed -i "0,/^\[Globals\]/s//[Globals]\nport=$PORT/" /etc/xrdp/xrdp.ini
fi
# All WSL2 distros share one network and with it the X display numbers, so
# each port gets its own range (the panel sets it again when the port changes).
if [ -f /etc/xrdp/sesman.ini ]; then
    OFFSET=$((10 + (PORT % 25) * 2))
    sed -i -E "s/^X11DisplayOffset=[0-9]+[[:space:]]*$/X11DisplayOffset=$OFFSET/" /etc/xrdp/sesman.ini
fi

# 3. Suppress Polkit authentication dialogs (colord & packagekit loop)
echo "==> Configuring Polkit policies to prevent color-manager popups..."
mkdir -p /etc/polkit-1/localauthority/50-local.d 2>/dev/null || true
cat <<'POLKIT_EOF' > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla 2>/dev/null || true
[Allow Colord and PackageKit for all users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile;org.freedesktop.packagekit.system-sources-refresh
ResultAny=no
ResultInactive=no
ResultActive=yes
POLKIT_EOF

# Modern Polkit JavaScript rule (/etc/polkit-1/rules.d/ for systemd distros)
mkdir -p /etc/polkit-1/rules.d 2>/dev/null || true
cat <<'JS_POLKIT_EOF' > /etc/polkit-1/rules.d/45-allow-colord.rules 2>/dev/null || true
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.color-manager.") === 0 ||
        action.id === "org.freedesktop.packagekit.system-sources-refresh") {
        return polkit.Result.YES;
    }
});
JS_POLKIT_EOF

# 4. Configure the desktop session files (.xsession & .xinitrc)
# The panel puts a write_session function (printing app/linux/xsession) in front of
# this script. Run by hand, read that file from next to this script instead.
if ! declare -F write_session >/dev/null; then
    write_session() { cat "$(dirname "$0")/xsession"; }
fi

mkdir -p /etc/skel
write_session > /etc/skel/.xsession
write_session > /etc/skel/.xinitrc

# Apply to root and existing user home directories
for H in /root /home/*; do
    [ -d "$H" ] || continue
    write_session > "$H/.xsession"
    write_session > "$H/.xinitrc"
    chown --reference="$H" "$H/.xsession" "$H/.xinitrc" 2>/dev/null || true
    chmod 644 "$H/.xsession" "$H/.xinitrc" 2>/dev/null || true
done

# 5. Add xrdp user to ssl-cert group if present
if getent group ssl-cert >/dev/null 2>&1; then
    usermod -aG ssl-cert xrdp 2>/dev/null || true
fi

# 6. Restart XRDp service
echo "==> Starting / Restarting xrdp service on port $PORT..."
if service xrdp restart >/dev/null 2>&1; then
    :
elif systemctl restart xrdp-sesman xrdp >/dev/null 2>&1; then
    :
else
    pkill -x xrdp >/dev/null 2>&1 || true
    pkill -x xrdp-sesman >/dev/null 2>&1 || true
    sleep 1
    (/usr/sbin/xrdp-sesman >/dev/null 2>&1 &)
    sleep 1
    (/usr/sbin/xrdp >/dev/null 2>&1 &)
fi

echo "DESK_SETUP_DONE"
exit 0
