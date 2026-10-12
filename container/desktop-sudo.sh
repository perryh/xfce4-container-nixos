#!/usr/bin/env bash
# Toggle passwordless sudo for the desktop user, or take it away. Run as root inside
# the container; build.sh passes "yes" when DESKTOP_SUDO=yes.
#
# The sudo rule itself is declarative (security.sudo.extraRules in nixos/users.nix);
# this only toggles membership in the desktop-nopasswd group. Anything running as
# the desktop user, including Brave, can then become root in the container. The
# container itself stays unprivileged.
set -euo pipefail

# incus exec does not give the shell the system path.
export PATH=/run/current-system/sw/bin:$PATH

USER_NAME=desktop
GROUP=desktop-nopasswd

if [ "${1:-no}" = yes ]; then
    gpasswd -a "$USER_NAME" "$GROUP" >/dev/null 2>&1 || true
    id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx "$GROUP" \
        || { echo "Could not add $USER_NAME to $GROUP." >&2; exit 1; }
    echo "Desktop sudo is on (passwordless, in-container only)."
else
    gpasswd -d "$USER_NAME" "$GROUP" >/dev/null 2>&1 || true
    echo "Desktop sudo is off."
fi
