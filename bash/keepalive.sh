#!/bin/bash
# ==============================================================================
# keepalive.sh
# Keeps the WSL VM running while an XFCE desktop session is active.
# Prevents WSL2 idle shutdown from killing the desktop session after launcher exit.
# Exits automatically once xfce4-session closes, allowing RAM to be freed.
# ==============================================================================

# Wait up to 5 minutes (300 iterations) for the session to start
for _ in $(seq 1 300); do
    pgrep -x xfce4-session >/dev/null 2>&1 && break
    sleep 1
done

# Keep running as long as xfce4-session is alive
while pgrep -x xfce4-session >/dev/null 2>&1; do
    sleep 5
done

exit 0
