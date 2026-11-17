#!/bin/sh
# ==============================================================================
# set-timezone.sh - sets the distro's clock to the Windows time zone.
# Many WSL images start on UTC, so the desktop clock is hours off.
#
# Usage: set-timezone.sh <IANA zone>   (e.g. Europe/Berlin, Asia/Kolkata)
# Windows may give an older alias (Asia/Calcutta). Newer tzdata keeps those
# only as links listed in tzdata.zi, so an alias is resolved through it.
# Exit codes: 2 bad zone name, 3 zone not found (nothing changed).
# ==============================================================================

ZONE="$1"
case "$ZONE" in
    ''|*..*|/*) echo "BAD_ZONE"; exit 2 ;;
esac
DIR=/usr/share/zoneinfo
if [ ! -f "$DIR/$ZONE" ] && [ -r "$DIR/tzdata.zi" ]; then
    TARGET=$(awk -v n="$ZONE" '$1 == "L" && $3 == n { print $2; exit }' "$DIR/tzdata.zi")
    [ -n "$TARGET" ] && ZONE="$TARGET"
fi
if [ ! -f "$DIR/$ZONE" ]; then
    echo "ZONE_NOT_FOUND: $ZONE"
    exit 3
fi
ln -sf "$DIR/$ZONE" /etc/localtime
echo "$ZONE" > /etc/timezone 2>/dev/null || true
echo "TIMEZONE_SET: $ZONE"
exit 0
