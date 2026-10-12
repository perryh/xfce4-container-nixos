#!/usr/bin/env bash
# Build the whole NixOS desktop on this machine with one command. Safe to re-run.
#
#   ./build.sh
#
# Give the desktop user passwordless sudo in the container (opt-in):
#   DESKTOP_SUDO=yes ./build.sh
# Run again without it to take sudo away.
#
# Publish the noVNC page on your tailnet (opt-in; replaces the Ubuntu repo's
# Cloudflare quick tunnel):
#   TAILSCALE=yes ./build.sh          tailnet-only, identity-gated
#   TAILSCALE=yes FUNNEL=yes ...      additionally public via Funnel
#
# The container's contents are built from the locked flake (nixos/), so the same
# checkout produces the same desktop on any machine, on any date. Version bumps
# are `nix flake update` plus a commit. After a flake change, a running container
# keeps its old image; build.sh notices and tells you how to recreate it
# (RECREATE=yes ./build.sh), which resets /home/desktop.
#
# Each step shows a spinner while it runs. Full output goes to build.log.
# On failure, fix the cause and re-run; finished steps are skipped.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
CT="${CT:-xfce}"
DESKTOP_USER=desktop
LOG="$REPO/build.log"
OUT="$REPO/out"
TOTAL_STAGES=9
STAGE_NO=0
CURRENT_STAGE=start
START_TIME=$SECONDS
TAILNET_URL=""
SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# Everything inside the container lives under the NixOS system path; incus exec
# does not put it on PATH, so use absolute paths.
CTBIN=/run/current-system/sw/bin

# ---- output ----------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m' DIM=$'\033[2m' RED=$'\033[31m' GREEN=$'\033[32m'
    YELLOW=$'\033[33m' CYAN=$'\033[36m' RESET=$'\033[0m'
else
    BOLD= DIM= RED= GREEN= YELLOW= CYAN= RESET=
fi
RULE=$(printf '─%.0s' $(seq 1 64))

info() { printf '  %s·%s %s\n' "$DIM" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }

stage() {
    STAGE_NO=$((STAGE_NO + 1))
    CURRENT_STAGE="$*"
    echo
    printf '%s%s%d/%d  %s%s\n' "$BOLD" "$CYAN" "$STAGE_NO" "$TOTAL_STAGES" "$*" "$RESET"
    printf '%s%s%s\n' "$DIM" "$RULE" "$RESET"
}

# Runs one step with a spinner. Output goes to build.log. Prints ✓ with the duration,
# or ✗ with the last lines of this step's output.
run_step() {
    local label=$1 started=$SECONDS mark rc=0 i=0 took
    shift
    mark=$(wc -l <"$LOG")
    # Carriage returns from progress bars become newlines, so the log reads line by line.
    if [ -t 1 ]; then
        ( "$@" </dev/null 2>&1 | tr '\r' '\n' >>"$LOG" ) &
        local pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  %s%s%s %s\033[K' "$CYAN" "${SPINNER[i % ${#SPINNER[@]}]}" "$RESET" "$label"
            i=$((i + 1))
            sleep 0.1
        done
        wait "$pid" || rc=$?
        printf '\r\033[K'
    else
        printf '  … %s\n' "$label"
        ( "$@" </dev/null 2>&1 | tr '\r' '\n' >>"$LOG" ) || rc=$?
    fi

    took=$((SECONDS - started))
    if [ "$rc" -eq 0 ]; then
        printf '  %s✓%s %s %s%ss%s\n' "$GREEN" "$RESET" "$label" "$DIM" "$took" "$RESET"
    else
        printf '  %s✗%s %s %s(exit %s)%s\n' "$RED" "$RESET" "$label" "$DIM" "$rc" "$RESET"
        tail -n +"$((mark + 1))" "$LOG" | tail -n 20 | sed "s/^/    ${DIM}│${RESET} /"
        return "$rc"
    fi
}

on_error() {
    echo >&2
    printf '%s%s✗ Build stopped during: %s%s\n' "$BOLD" "$RED" "$CURRENT_STAGE" "$RESET" >&2
    printf '  Full output: %s\n' "$LOG" >&2
    printf '  Fix the cause and run ./build.sh again. Finished steps are skipped.\n' >&2
}
trap on_error ERR

# ---- nix -------------------------------------------------------------------

# The one new host dependency. The Determinate Systems installer is the standard
# non-interactive way to get a multi-user Nix with flakes on Ubuntu.
ensure_nix() {
    if command -v nix >/dev/null 2>&1; then
        return 0
    fi
    echo "nix not found; installing it with the Determinate Systems nix-installer."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
        | sh -s -- install
    export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
    command -v nix >/dev/null 2>&1 \
        || { echo "Installed nix but it is not on PATH yet; re-run ./build.sh." >&2; return 1; }
}

nix() { command nix --extra-experimental-features 'nix-command flakes' "$@"; }

# Builds the split image from the locked flake and records the paths and the
# rootfs hash in out/image.env for the stages below.
build_image() {
    local rootfs_out meta_out rootfs_tar sha
    rootfs_out=$(nix build --no-link --print-out-paths .#rootfs) || return 1
    meta_out=$(nix build --no-link --print-out-paths .#metadata) || return 1
    rootfs_tar=$(find "$rootfs_out" -name '*.tar.xz' -type f | head -n 1)
    [ -n "$rootfs_tar" ] || { echo "No rootfs tarball under $rootfs_out." >&2; return 1; }
    [ -f "$meta_out/metadata.tar.gz" ] || { echo "No metadata.tar.gz under $meta_out." >&2; return 1; }
    sha=$(sha256sum "$rootfs_tar" | cut -d' ' -f1)
    install -d "$OUT"
    {
        echo "ROOTFS_TAR=$rootfs_tar"
        echo "META_TAR=$meta_out/metadata.tar.gz"
        echo "ROOTFS_SHA=$sha"
    } >"$OUT/image.env"
    echo "rootfs:   $rootfs_tar"
    echo "metadata: $meta_out/metadata.tar.gz"
    echo "rootfs sha256: $sha"
}

# ---- container helpers -----------------------------------------------------

incus_ct() {
    sudo incus exec "$CT" -- "$@"
}

incus_user() {
    local uid=$1
    shift
    sudo incus exec "$CT" --user "$uid" --group "$uid" \
        --env HOME="/home/$DESKTOP_USER" -- "$@"
}

user_systemctl() {
    local uid=$1 runtime="/run/user/$1"
    shift
    incus_user "$uid" env \
        XDG_RUNTIME_DIR="$runtime" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
        "$CTBIN/systemctl" --user "$@"
}

desktop_uid() {
    incus_ct "$CTBIN/id" -u "$DESKTOP_USER"
}

fix_subuid() {
    sudo usermod -v 1000000-1999999 -w 1000000-1999999 root
    if systemctl is-active --quiet incus.service; then
        sudo systemctl restart incus.service
    fi
}

wait_for_container() {
    local state
    for _ in $(seq 1 90); do
        state=$(incus_ct "$CTBIN/systemctl" is-system-running 2>/dev/null || true)
        case "$state" in
            running | degraded) return 0 ;;
        esac
        sleep 2
    done
    echo "Container $CT did not finish booting." >&2
    return 1
}

wait_for_network() {
    for _ in $(seq 1 60); do
        if incus_ct "$CTBIN/bash" -c \
            'timeout 10 /run/current-system/sw/bin/bash -c "exec 3<>/dev/tcp/archive.ubuntu.com/80"' \
            >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    echo "Container $CT cannot resolve or reach archive.ubuntu.com yet." >&2
    return 1
}

# Push a script into the container and run it with bash. The image contains the
# whole system, so nothing else from this repo needs copying.
push_and_run() {
    local file=$1 base
    shift
    base=$(basename "$file")
    sudo incus file push "$REPO/$file" "$CT/tmp/$base"
    incus_ct "$CTBIN/bash" "/tmp/$base" "$@"
}

# Waits until the VNC port and the XFCE session are both up. On failure, writes the
# unit status and journal to the log.
wait_for_desktop() {
    local uid
    uid=$(desktop_uid)
    for _ in $(seq 1 30); do
        if incus_ct /bin/sh -c 'test -S /tmp/.X11-unix/X1' 2>/dev/null \
            && incus_ct "$CTBIN/ss" -ltn | grep -q '127.0.0.1:5901'; then
            return 0
        fi
        # The session can start and then exit, so stop early once its unit has stopped.
        user_systemctl "$uid" is-active --quiet xfce-session.service || break
        sleep 1
    done
    {
        user_systemctl "$uid" --no-pager status xfce-vnc.service xfce-session.service || true
        sudo incus exec "$CT" --user "$uid" --group "$uid" \
            --env HOME="/home/$DESKTOP_USER" --env XDG_RUNTIME_DIR="/run/user/$uid" \
            "$CTBIN/journalctl" --user --no-pager -n 80 || true
    } >>"$LOG" 2>&1
    echo "The XFCE session did not stay up on display :1." >&2
    return 1
}

# Brave's sandbox needs the same host userns setting as Chrome's did.
check_browser_sandbox() {
    local uid out
    uid=$(desktop_uid)
    out=$(mktemp)
    if ! sudo incus exec "$CT" --user "$uid" --group "$uid" \
        --env HOME="/home/$DESKTOP_USER" -- \
        "$CTBIN/timeout" 90 "$CTBIN/brave" \
        --headless=new --disable-gpu --no-first-run --dump-dom about:blank \
        >"$out" 2>&1; then
        echo "Brave failed to start with its sandbox for $DESKTOP_USER:" >&2
        tail -n 20 "$out" >&2
        rm -f "$out"
        return 1
    fi
    rm -f "$out"
}

# Checks that the gateway and VNC proxy listen on loopback only.
check_loopback() {
    local listen="" port
    for _ in $(seq 1 30); do
        listen=$(ss -ltn)
        if grep -q '127.0.0.1:6080' <<<"$listen" && grep -q '127.0.0.1:5901' <<<"$listen"; then
            break
        fi
        sleep 2
    done
    for port in 5901 6080; do
        if ! grep -q "127.0.0.1:$port" <<<"$listen"; then
            echo "Port $port is not listening on 127.0.0.1." >&2
            return 1
        fi
    done
    if grep -Eq '(0\.0\.0\.0|\[::\]|\*):(5901|6080)' <<<"$listen"; then
        echo "The VNC proxy or noVNC is listening beyond loopback. Refusing to continue." >&2
        return 1
    fi
}

# ---- run -------------------------------------------------------------------

: >"$LOG"

echo
printf '%s  xfce4-container-nixos%s\n' "$BOLD" "$RESET"
printf '  %sNixOS 26.05 (flake-pinned) · container %s · XFCE on :1 · noVNC on 127.0.0.1:6080%s\n' \
    "$DIM" "$CT" "$RESET"

stage "Host checks"
info "Asking for sudo once, so the steps below run unattended."
sudo -v
run_step "Preflight" "$REPO/host/preflight.sh" || true
if ! grep -q '^root:' /etc/subuid || ! grep -q '^root:' /etc/subgid; then
    run_step "Root subordinate ID range for Incus" fix_subuid
fi

stage "Nix and image build"
run_step "Ensure Nix (Determinate Systems installer)" ensure_nix
run_step "Build the container image from the locked flake" build_image
# shellcheck disable=SC1091
. "$OUT/image.env"
info "Image content sha256: ${ROOTFS_SHA:0:16}…"

stage "Host packages and container"
run_step "Install host packages, import image, launch container '$CT'" \
    env CT="$CT" ROOTFS_TAR="$ROOTFS_TAR" META_TAR="$META_TAR" \
    sudo -E "$REPO/host/bootstrap-incus.sh"
run_step "Wait for the container to boot" wait_for_container
run_step "Wait for container networking" wait_for_network

stage "Verify desktop"
run_step "Allow user namespaces on the host (Brave sandbox)" sudo "$REPO/host/allow-userns.sh"
run_step "Wait for XFCE on :1 and VNC on 127.0.0.1:5901" wait_for_desktop
run_step "Brave sandbox check" check_browser_sandbox

stage "Desktop sudo"
run_step "Desktop sudo: ${DESKTOP_SUDO:-no}" \
    push_and_run container/desktop-sudo.sh "${DESKTOP_SUDO:-no}"

stage "Login and noVNC gateway"
run_step "Create login and install gateway service" \
    env CT="$CT" sudo -E "$REPO/host/install-novnc.sh"
run_step "Check that the gateway listens on loopback only" check_loopback

stage "Resource limits"
run_step "Apply container and gateway limits" \
    env CT="$CT" sudo -E "$REPO/host/resource-policy.sh"

stage "Docker checks"
run_step "Build, Compose, and published-port test" \
    push_and_run container/docker-check.sh

stage "Tailnet access (opt-in)"
if [ "${TAILSCALE:-}" = yes ]; then
    run_step "Publish noVNC on the tailnet (Tailscale)" \
        env FUNNEL="${FUNNEL:-no}" sudo -E "$REPO/host/install-tailscale.sh"
    TAILNET_URL=$(sudo tailscale serve status 2>/dev/null | grep -o 'https://[^ ]*' | head -n 1 || true)
else
    info "Skipped. Run TAILSCALE=yes ./build.sh to publish noVNC on your tailnet."
fi

# ---- summary ---------------------------------------------------------------

ELAPSED=$((SECONDS - START_TIME))
echo
printf '%s%s✓ Desktop is ready%s  %s(%dm%02ds)%s\n' "$BOLD" "$GREEN" "$RESET" \
    "$DIM" $((ELAPSED / 60)) $((ELAPSED % 60)) "$RESET"
echo
printf '  %sOpen%s      http://127.0.0.1:6080/vnc.html\n' "$BOLD" "$RESET"
printf '  %sLogin%s     user %sdesktop%s, password: sudo grep NOVNC_AUTH /etc/xfce4-container/auth.env\n' \
    "$BOLD" "$RESET" "$CYAN" "$RESET"
printf '  %sImage%s     content sha256 %s\n' "$BOLD" "$RESET" "${ROOTFS_SHA:0:16}"
if [ -n "$TAILNET_URL" ]; then
    printf '  %sTailnet%s   %s  %s(login required)%s\n' "$BOLD" "$RESET" "$TAILNET_URL" "$DIM" "$RESET"
fi
printf '  %sLog%s       %s\n' "$BOLD" "$RESET" "$LOG"
