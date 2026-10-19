#!/bin/bash
# ==============================================================================
# install-desktop.sh
# Auto-installs XFCE desktop + xrdp on any major Linux distribution under WSL.
# Configures xrdp to listen on specified port (default: 3390).
# Configures Polkit to suppress annoying authentication prompts (colord/packagekit).
# Configures WSLg PulseAudio forwarding for sound support.
#
# Usage: ./install-desktop.sh [PORT]
# Example: ./install-desktop.sh 3390
# ==============================================================================

PORT="${1:-3390}"
echo "==> Starting desktop environment installation (Target Port: $PORT)..."

# 1. Package manager installers
install_apt() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y xfce4 xfce4-goodies xrdp dbus-x11
}

install_dnf() {
    dnf install -y xrdp xorgxrdp
    dnf group install -y "Xfce Desktop" || dnf groupinstall -y "Xfce" || dnf install -y @xfce-desktop-environment
}

install_yum() {
    yum install -y epel-release || true
    yum groupinstall -y "Xfce" || true
    yum install -y xrdp
}

install_zypper() {
    zypper --non-interactive install xrdp
    zypper --non-interactive install -t pattern xfce
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
    pacman -Syu --needed --noconfirm base-devel git sudo xfce4 xorg-server
    
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
    PM=apt; echo "Detected package manager: apt"; install_apt
elif command -v dnf >/dev/null 2>&1; then
    PM=dnf; echo "Detected package manager: dnf"; install_dnf
elif command -v zypper >/dev/null 2>&1; then
    PM=zypper; echo "Detected package manager: zypper"; install_zypper
elif command -v yum >/dev/null 2>&1; then
    PM=yum; echo "Detected package manager: yum"; install_yum
elif command -v pacman >/dev/null 2>&1; then
    PM=pacman; echo "Detected package manager: pacman"; install_pacman
else
    echo "UNKNOWN_PKG_MANAGER"
    exit 21
fi
set +e

# 2. Configure XRDp port in /etc/xrdp/xrdp.ini
if [ -f /etc/xrdp/xrdp.ini ]; then
    echo "==> Configuring xrdp to listen on port $PORT..."
    # Only the [Globals] "port=<digits>" line: the [Xorg]/[Xvnc] sections have
    # "port=-1", which must stay exactly as it is.
    sed -i -E "/^\[Globals\]/,/^\[/ s/^port=[0-9]+[[:space:]]*$/port=$PORT/" /etc/xrdp/xrdp.ini
    grep -Eq "^port=$PORT[[:space:]]*$" /etc/xrdp/xrdp.ini || sed -i "0,/^\[Globals\]/s//[Globals]\nport=$PORT/" /etc/xrdp/xrdp.ini
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

# 4. Configure default XFCE session files (.xsession & .xinitrc)
write_session() {
    cat <<'SESSION_EOF'
# Force X11 so XFCE renders inside Remote Desktop (xrdp), not via WSLg Wayland.
unset WAYLAND_DISPLAY
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export XDG_SESSION_TYPE=x11

# Route audio to WSLg PulseAudio server for working sound
if [ -e /mnt/wslg/PulseServer ]; then
    export PULSE_SERVER=/mnt/wslg/PulseServer
fi

exec startxfce4
SESSION_EOF
}

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
getent group ssl-cert >/dev/null 2>&1 && usermod -aG ssl-cert xrdp 2>/dev/null || true

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
