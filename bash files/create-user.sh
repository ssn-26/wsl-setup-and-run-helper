#!/bin/bash
# ==============================================================================
# create-user.sh
# Create or update a Linux user with sudo/wheel privileges and XFCE desktop session.
# Executed as root inside the target WSL distro.
# Usage: ./create-user.sh <username>
# Password is set separately via stdin piping to chpasswd.
# ==============================================================================

set -e

USERNAME="$1"
if [ -z "$USERNAME" ]; then
    echo "Error: No username specified." >&2
    exit 1
fi

# 1. Create the user if it doesn't already exist
if ! id -u "$USERNAME" >/dev/null 2>&1; then
    echo "  - Creating Linux user '$USERNAME'..."
    useradd -m -s /bin/bash "$USERNAME"
else
    echo "  - Linux user '$USERNAME' already exists."
fi

# 2. Grant administrative privileges (sudo or wheel)
echo "  - Configuring admin rights for '$USERNAME'..."

# Minimal images (Arch, some Debian builds) ship without the sudo program.
# A failed install only warns: the user is still created, just without sudo.
install_sudo() {
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq sudo >/dev/null
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q sudo
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive --quiet install sudo
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q sudo
    elif command -v pacman >/dev/null 2>&1; then
        if ! pacman-key --list-keys 2>/dev/null | grep -q '^pub'; then
            echo "  - Initializing pacman keys (first run)..."
            pacman-key --init >/dev/null 2>&1
            pacman-key --populate archlinux >/dev/null 2>&1
        fi
        pacman -Syu --needed --noconfirm sudo >/dev/null
    else
        return 1
    fi
}

if ! command -v sudo >/dev/null 2>&1; then
    echo "  - Installing the sudo package..."
    install_sudo || true
fi

# Use the distro's admin group; if it has neither, create "wheel".
if getent group sudo >/dev/null 2>&1; then
    ADMIN_GROUP=sudo
elif getent group wheel >/dev/null 2>&1; then
    ADMIN_GROUP=wheel
else
    echo "  - No 'sudo' or 'wheel' group found - creating 'wheel'..."
    groupadd wheel
    ADMIN_GROUP=wheel
fi
usermod -aG "$ADMIN_GROUP" "$USERNAME"

# Make sure that group is allowed to use sudo (Arch ships %wheel commented out).
if ! grep -Eqs "^[[:space:]]*%$ADMIN_GROUP[[:space:]]" /etc/sudoers /etc/sudoers.d/*; then
    mkdir -p /etc/sudoers.d
    echo "%$ADMIN_GROUP ALL=(ALL:ALL) ALL" > "/etc/sudoers.d/10-$ADMIN_GROUP"
    chmod 440 "/etc/sudoers.d/10-$ADMIN_GROUP"
fi

if ! command -v sudo >/dev/null 2>&1; then
    echo "  - WARNING: sudo could not be installed, so '$USERNAME' has no admin rights yet."
    echo "    Check the internet connection inside the distro, then add the account again."
fi

# 3. Configure XFCE Desktop session files (.xsession & .xinitrc)
# Forces X11 mode so XFCE renders inside Remote Desktop instead of WSLg.
# Routes audio to WSLg's PulseAudio server for working sound.
echo "  - Setting up XFCE session and audio forwarding..."
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
USER_HOME="${USER_HOME:-/home/$USERNAME}"

for FILE in .xsession .xinitrc; do
    cat <<'SESSION_EOF' > "$USER_HOME/$FILE"
# Force X11 so XFCE renders inside Remote Desktop (xrdp), not via WSLg Wayland.
unset WAYLAND_DISPLAY
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export XDG_SESSION_TYPE=x11

# Route audio to WSLg PulseAudio bridge for working sound in Remote Desktop
if [ -e /mnt/wslg/PulseServer ]; then
    export PULSE_SERVER=/mnt/wslg/PulseServer
fi

exec startxfce4
SESSION_EOF

    # "user:" = the user's own login group (on openSUSE that is "users", not
    # a group named after the user).
    chown "$USERNAME:" "$USER_HOME/$FILE" 2>/dev/null || true
    chmod 644 "$USER_HOME/$FILE" 2>/dev/null || true
done

echo "  - User '$USERNAME' configuration complete."
exit 0
