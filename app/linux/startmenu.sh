#!/bin/sh
# ==============================================================================
# startmenu.sh - keeps a distro's Linux apps out of the Windows Start menu.
#
# WSLg puts every app in /usr/share/applications (and /usr/local/share/...) in
# the Windows Start menu, unless its .desktop file says NoDisplay=true. A
# desktop install adds a dozen apps there that are meant for the Linux desktop.
#
#   hide    each app's .desktop file gets NoDisplay=true (so Windows skips it)
#           and an unchanged copy goes to /usr/share/wsl-panel/applications,
#           a folder WSLg does not read. The Linux desktop reads it first
#           (XDG_DATA_DIRS, set in /etc/profile.d and the session file), so
#           the apps stay in the Linux menu. App store apps (links into
#           Flatpak's folder) are left alone: they are installed for Windows.
#           A package-manager hook repeats this after every install/update.
#   show    puts the original files back and removes the hook.
#   status  prints HIDDEN or SHOWN.
#
# Usage: startmenu.sh hide|show|status
# ==============================================================================

ACTION="${1:-status}"
APPS=/usr/share/applications
COPIES=/usr/share/wsl-panel/applications
MARK=X-WSL-Panel-Hidden=true
FLAG=/etc/wsl-panel-hide-apps
SELF=/usr/local/sbin/wsl-panel-startmenu
PROFILE=/etc/profile.d/wsl-panel-apps.sh

hide_all() {
    mkdir -p "$COPIES"
    for f in "$APPS"/*.desktop; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue                       # App store app (Flatpak link)
        grep -q "^$MARK" "$f" && continue             # hidden already
        grep -q '^NoDisplay=true' "$f" && continue    # hidden by its package
        cp -f "$f" "$COPIES/"
        # The keys go first in the [Desktop Entry] group; any NoDisplay line of
        # the original is dropped (the copy keeps it).
        sed -i -e '/^NoDisplay=/d' -e "0,/^\[Desktop Entry\]/s//[Desktop Entry]\nNoDisplay=true\n$MARK/" "$f"
    done
    # Copies of apps that were uninstalled since.
    for c in "$COPIES"/*.desktop; do
        [ -f "$c" ] || continue
        [ -e "$APPS/$(basename "$c")" ] || rm -f "$c"
    done
}

show_all() {
    for c in "$COPIES"/*.desktop; do
        [ -f "$c" ] || continue
        f="$APPS/$(basename "$c")"
        if [ -f "$f" ] && grep -q "^$MARK" "$f"; then cp -f "$c" "$f"; fi
        rm -f "$c"
    done
}

install_hooks() {
    cp -f "$0" "$SELF" 2>/dev/null && chmod 755 "$SELF"
    # The variables are written as text, for the login shell to expand later.
    # shellcheck disable=SC2016
    printf '# Written by the WSL Control Panel: the Linux desktop reads its own copies of\n# the apps hidden from the Windows Start menu.\ncase ":${XDG_DATA_DIRS}:" in *:/usr/share/wsl-panel:*) ;; *) export XDG_DATA_DIRS="/usr/share/wsl-panel:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" ;; esac\n' > "$PROFILE"
    if [ -d /etc/apt/apt.conf.d ]; then
        printf 'DPkg::Post-Invoke { "[ -f %s ] && [ -x %s ] && %s hide >/dev/null 2>&1 || true"; };\n' "$FLAG" "$SELF" "$SELF" > /etc/apt/apt.conf.d/99wsl-panel-startmenu
    fi
    if [ -d /etc/pacman.d ]; then
        mkdir -p /etc/pacman.d/hooks
        printf '[Trigger]\nType = Path\nOperation = Install\nOperation = Upgrade\nTarget = usr/share/applications/*.desktop\n\n[Action]\nDescription = Keeping Linux apps out of the Windows Start menu\nWhen = PostTransaction\nExec = /bin/sh -c "[ -f %s ] && %s hide || true"\n' "$FLAG" "$SELF" > /etc/pacman.d/hooks/wsl-panel-startmenu.hook
    fi
}

remove_hooks() {
    rm -f /etc/apt/apt.conf.d/99wsl-panel-startmenu /etc/pacman.d/hooks/wsl-panel-startmenu.hook "$PROFILE"
}

case "$ACTION" in
    hide)
        touch "$FLAG"
        hide_all
        # Only when run by the panel (not from the hook, which runs the copy).
        [ "$0" = "$SELF" ] || install_hooks
        echo "HIDDEN"
        ;;
    show)
        rm -f "$FLAG"
        show_all
        remove_hooks
        echo "SHOWN"
        ;;
    status)
        if [ -f "$FLAG" ]; then echo "HIDDEN"; else echo "SHOWN"; fi
        ;;
    *)
        echo "Usage: startmenu.sh hide|show|status"; exit 2 ;;
esac
exit 0
