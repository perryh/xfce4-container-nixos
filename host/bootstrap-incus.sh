#!/usr/bin/env bash
# Install host packages (Ubuntu), import the NixOS image built from the flake, and
# launch the container. Idempotent: every step checks whether it already happened.
#
# Called by build.sh as root with CT, ROOTFS_TAR, and META_TAR in the environment.
#
# If you want a custom storage pool, run `sudo incus admin init` by hand first.
# Otherwise this runs `incus admin init --minimal` (dir-backed pool and NAT bridge).
set -euo pipefail

CT="${CT:-xfce}"
NET="${NET:-incusbr0}"
ALIAS=xfce-nixos
ROOTFS_TAR="${ROOTFS_TAR:?set ROOTFS_TAR to the built rootfs tarball}"
META_TAR="${META_TAR:?set META_TAR to the built metadata tarball}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

wait_for_ipv4() {
    local addrs
    for _ in $(seq 1 30); do
        addrs=$(incus list "$CT" --format csv -c 4)
        if grep -Eq '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' <<<"$addrs"; then
            return 0
        fi
        sleep 2
    done
    return 1
}

if ! dpkg -s incus websockify novnc >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y incus websockify novnc
fi

systemctl enable --now incus.service

if [ -z "$(incus storage list --format csv)" ]; then
    incus admin init --minimal
fi

# Which image the running container was created from, if any.
CURRENT_FP=""
if incus info "$CT" >/dev/null 2>&1; then
    CURRENT_FP=$(incus config get "$CT" volatile.base_image 2>/dev/null || true)
fi

# Drop images from earlier builds; keep the one this container runs, if any.
for fp in $(incus image list "$ALIAS" --format csv -c f); do
    [ "$fp" = "$CURRENT_FP" ] || incus image delete "$fp" 2>/dev/null || true
done

# Import. Incus dedups by fingerprint, so re-importing identical content fails
# harmlessly; that is fine as long as the alias still resolves to an image.
if ! incus image import "$META_TAR" "$ROOTFS_TAR" --alias "$ALIAS" 2>&1; then
    if [ -z "$(incus image list "$ALIAS" --format csv -c f)" ]; then
        echo "incus image import failed." >&2
        exit 1
    fi
    echo "Image content already present in the image store; keeping it."
fi

# The list may hold two rows right after a content change (old + new, same alias).
# The new fingerprint is whichever one the container is not running.
NEW_FP="$CURRENT_FP"
for fp in $(incus image list "$ALIAS" --format csv -c f); do
    [ "$fp" != "$CURRENT_FP" ] && NEW_FP="$fp"
done
[ -n "$NEW_FP" ] || { echo "No image under alias $ALIAS." >&2; exit 1; }

if incus info "$CT" >/dev/null 2>&1; then
    if [ "$CURRENT_FP" != "$NEW_FP" ]; then
        echo "Container '$CT' was built from a different image:"
        echo "  running: $CURRENT_FP"
        echo "  built:   $NEW_FP"
        if [ "${RECREATE:-}" = yes ]; then
            echo "RECREATE=yes: deleting and relaunching '$CT' (this resets /home/desktop)."
            incus delete "$CT" --force
        else
            echo "Recreate it (this resets /home/desktop!) with:  RECREATE=yes ./build.sh" >&2
            exit 1
        fi
    fi
else
    # No limits.memory, limits.cpu, or security.privileged on purpose.
    incus launch "$NEW_FP" "$CT" \
        -c boot.autostart=true \
        -c security.nesting=true \
        -c security.syscalls.intercept.mknod=true \
        -c security.syscalls.intercept.setxattr=true
fi

# With UFW active, its default policy rejects incoming and routed traffic. That blocks
# DHCP and DNS from the Incus bridge. Allow the bridge explicitly. Rules are idempotent.
UFW_STATE=$(ufw status 2>/dev/null || true)
if grep -q '^Status: active' <<<"$UFW_STATE"; then
    ufw allow in on "$NET"
    ufw route allow in on "$NET"
    ufw route allow out on "$NET"
fi

if ! wait_for_ipv4; then
    echo "Container $CT has no IPv4 address yet; restarting it to retry DHCP."
    incus restart "$CT"
    if ! wait_for_ipv4; then
        echo "Container $CT still has no IPv4 address. Check UFW and dnsmasq for $NET." >&2
        exit 1
    fi
fi
