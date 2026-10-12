#!/usr/bin/env bash
# Optional: publish noVNC on your tailnet with Tailscale, instead of a public
# Cloudflare quick tunnel. Run as root (build.sh calls it with TAILSCALE=yes):
#   sudo host/install-tailscale.sh           tailnet-only (identity-gated)
#   FUNNEL=yes sudo host/install-tailscale.sh  also public via Funnel
#
# `tailscale serve` proxies https://<host>.ts.net to 127.0.0.1:6080, so the gateway
# keeps listening on loopback only. Tailnet access needs your Tailscale identity on
# top of the noVNC login. FUNNEL=yes additionally exposes it to the public internet
# (requires Funnel enabled for the tailnet); the Basic-auth login is the only gate
# then, so keep it off unless you need public access.
#
# The apt package is the one host piece that floats; see the README.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

KEYRING=/usr/share/keyrings/tailscale-archive-keyring.gpg
SOURCES=/etc/apt/sources.list.d/tailscale.list

# Install from Tailscale's signed apt repository. The "noble" suite works on any
# recent Ubuntu; the package is effectively static binaries.
if ! command -v tailscale >/dev/null 2>&1; then
    install -d -m 755 /usr/share/keyrings
    curl -fsSL -o "$KEYRING" https://pkgs.tailscale.com/stable/ubuntu/noble.gpg
    echo "deb [signed-by=$KEYRING] https://pkgs.tailscale.com/stable/ubuntu noble main" >"$SOURCES"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tailscale
fi

systemctl enable --now tailscaled

# Authenticate. `tailscale up` prints a login URL and blocks until it is used;
# give up after five minutes so the build fails instead of hanging.
if ! tailscale status >/dev/null 2>&1; then
    UP_LOG=$(mktemp)
    timeout 300 tailscale up --accept-dns=false --accept-routes=false >"$UP_LOG" 2>&1 &
    UP_PID=$!
    for _ in $(seq 1 20); do
        URL=$(grep -o 'https://login.tailscale.com[^ ]*' "$UP_LOG" | tail -n 1 || true)
        [ -n "$URL" ] && break
        sleep 1
    done
    if [ -n "$URL" ]; then
        echo "Authenticate this host in the browser: $URL"
    fi
    wait "$UP_PID"
    rm -f "$UP_LOG"
fi

# Serve the gateway on the tailnet (idempotent).
tailscale serve status >/dev/null 2>&1 || tailscale serve --bg http://127.0.0.1:6080

if [ "${FUNNEL:-no}" = yes ]; then
    tailscale funnel --bg http://127.0.0.1:6080 || {
        echo "Funnel failed. It must be enabled for the tailnet (HTTPS certificates too)." >&2
        exit 1
    }
fi

echo "noVNC on the tailnet (login required):"
tailscale serve status
