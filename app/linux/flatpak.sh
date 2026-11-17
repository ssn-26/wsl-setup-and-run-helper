#!/bin/bash
# ==============================================================================
# flatpak.sh
# The Linux side of the panel's App store: Flatpak apps from Flathub.
# Executed as root inside the target WSL distro.
#
# Usage: ./flatpak.sh install <app-id>   sets Flatpak up (first time) and installs
#        ./flatpak.sh remove  <app-id>   uninstalls it and unused runtimes
#        ./flatpak.sh list               prints "<app-id><TAB><name>" per app,
#                                        or NO_FLATPAK when Flatpak is not set up
#
# Apps are installed system-wide, so every user of the distro can run them.
# Their .desktop files are linked into /usr/share/applications, where WSLg
# looks for apps to put in the Windows Start menu.
# ==============================================================================

ACTION="${1:-}"
APP="${2:-}"
EXPORTS=/var/lib/flatpak/exports/share/applications

# The same rule as Flathub uses for app ids (e.g. org.gimp.GIMP).
valid_id() { printf '%s' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_.-]{5,254}$'; }

install_flatpak_package() {
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update && apt-get install -y flatpak
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y flatpak
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install flatpak
    elif command -v yum >/dev/null 2>&1; then
        yum install -y flatpak
    elif command -v pacman >/dev/null 2>&1; then
        if ! pacman-key --list-keys 2>/dev/null | grep -q '^pub'; then
            pacman-key --init >/dev/null 2>&1
            pacman-key --populate archlinux >/dev/null 2>&1
        fi
        pacman -Syu --needed --noconfirm flatpak
    else
        echo "UNKNOWN_PKG_MANAGER"
        exit 21
    fi
}

setup_flatpak() {
    if ! command -v flatpak >/dev/null 2>&1; then
        echo "==> Setting up Flatpak (only the first time)..."
        install_flatpak_package
        if ! command -v flatpak >/dev/null 2>&1; then
            echo "FLATPAK_INSTALL_FAILED"
            exit 24
        fi
    fi
    if ! flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
        echo "FLATHUB_UNREACHABLE: Flathub (dl.flathub.org) could not be reached from inside the distro."
        exit 25
    fi
}

# Links the apps' Start menu entries where WSLg finds them, and removes links
# of apps that were uninstalled.
sync_menu_links() {
    mkdir -p /usr/share/applications
    for f in "$EXPORTS"/*.desktop; do
        [ -e "$f" ] || continue
        ln -sf "$f" "/usr/share/applications/$(basename "$f")"
    done
    for l in /usr/share/applications/*.desktop; do
        [ -L "$l" ] || continue
        case "$(readlink "$l")" in
            "$EXPORTS"/*) [ -e "$l" ] || rm -f "$l" ;;
        esac
    done
}

case "$ACTION" in
    install)
        valid_id "$APP" || { echo "BAD_APP_ID"; exit 2; }
        setup_flatpak || exit $?
        echo "==> Installing $APP from Flathub (the first app also downloads a shared runtime)..."
        flatpak install --system -y --noninteractive flathub "$APP"
        rc=$?
        sync_menu_links
        [ "$rc" = 0 ] && echo "FLATPAK_DONE"
        exit "$rc"
        ;;
    remove)
        valid_id "$APP" || { echo "BAD_APP_ID"; exit 2; }
        command -v flatpak >/dev/null 2>&1 || { echo "NO_FLATPAK"; exit 0; }
        echo "==> Uninstalling $APP ..."
        flatpak uninstall --system -y --noninteractive "$APP"
        rc=$?
        echo "==> Removing runtimes no app needs any more ..."
        flatpak uninstall --system -y --noninteractive --unused || true
        sync_menu_links
        [ "$rc" = 0 ] && echo "FLATPAK_DONE"
        exit "$rc"
        ;;
    list)
        command -v flatpak >/dev/null 2>&1 || { echo "NO_FLATPAK"; exit 0; }
        flatpak list --system --app --columns=application,name 2>/dev/null
        exit 0
        ;;
    *)
        echo "Usage: $0 install <app-id> | remove <app-id> | list" >&2
        exit 2
        ;;
esac
