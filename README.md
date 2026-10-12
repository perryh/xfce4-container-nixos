# xfce4-container-nixos

An Incus container running an XFCE desktop with a macOS-style look, reached from a
browser through noVNC on the host's loopback interface — the same architecture as
[xfce4-container](../xfce4-container), but the container runs **NixOS 26.05 built
from a locked flake**, so the desktop is reproducible: the same checkout builds the
same container contents on any machine, on any date.

## What you get

- **Container:** NixOS 26.05 (unprivileged), nested containers enabled (Docker runs
  inside). Everything in it — packages, config, services, theme — is declared in
  `nixos/` and pinned by `flake.lock`.
- **Desktop:** XFCE on a TigerVNC display (`:1`), WhiteSur GTK/icons/cursors
  (pinned by rev + hash), Inter and JetBrains Mono fonts, a translucent top bar, a
  Plank dock with Brave and the terminal, and a Catppuccin terminal palette.
- **Browser:** **Brave**, exactly pinned by the flake. (Google only publishes a
  "current" Chrome, which cannot be pinned; Brave is packaged in nixpkgs from
  hashed release tarballs.) Its sandbox needs the same host user-namespace setting
  Chrome did (`host/allow-userns.sh`).
- **Access:** noVNC at `http://127.0.0.1:6080/vnc.html` on the host, behind a
  Basic-auth login. The optional Tailscale stage publishes that page on your
  tailnet (identity-gated) instead of a public Cloudflare URL.

## Reproducibility — what is pinned, what floats

| Piece | Pinned? |
|---|---|
| Everything inside the container | **Yes** — `flake.lock` freezes the exact nixpkgs commit: XFCE, Brave, fonts, Docker, services, configs |
| WhiteSur themes | **Yes** — fetched by exact rev + sha256 (`nixos/theme-pkgs/`) |
| Wallpaper | **Yes** — generated deterministically with ffmpeg, no download |
| The built image | **Yes** — same lock ⇒ same store paths ⇒ same rootfs tarball (Incus dedups it by fingerprint) |
| Host packages (incus, websockify, novnc) | No — Ubuntu apt at install time |
| Tailscale (host) | No — Tailscale's apt repo at install time |
| The nix-installer script | No — installs the current Determinate Systems release, once |
| noVNC login password | Random by design, created once and kept across re-runs |

Moving to a new nixpkgs (e.g. 26.11 after 26.05 reaches end of life on
**2026-12-31**) is a one-line change to the `nixpkgs.url` in `flake.nix` plus
`nix flake update`, committed. Until then, rebuilding from the same lock reproduces
the same desktop bit-for-bit.

## Requirements

- Ubuntu host with `sudo` access and a working `apt`. Nix is installed
  automatically on first run (Determinate Systems installer) — the one new host
  dependency.
- Enough disk for the container image, XFCE, Brave, and Docker images. The exact
  size depends on what you run.

## Build

```bash
./build.sh
```

The script is safe to re-run. Each stage checks its own state and skips finished
work. To give the desktop user passwordless sudo inside the container (run again
without the variable to take it away):

```bash
DESKTOP_SUDO=yes ./build.sh
```

To publish the login page on your tailnet:

```bash
TAILSCALE=yes ./build.sh          # tailnet-only; add FUNNEL=yes for public access
```

### After a flake change

The running container keeps the image it was created from. A later `./build.sh`
notices the new image and stops with instructions; recreate the container (this
resets `/home/desktop`) with:

```bash
RECREATE=yes ./build.sh
```

## Stages

Each stage prints a numbered banner, and every step shows a spinner and its
duration. Full output goes to `build.log`.

| # | Stage | What it does |
|---|-------|--------------|
| 1 | Host checks | Caches sudo, preflight (incl. nix), and the root subordinate ID range Incus needs |
| 2 | Nix and image build | Ensures Nix; builds the rootfs + metadata tarballs from the locked flake |
| 3 | Host packages and container | Installs Incus, noVNC, websockify; imports the image; launches `xfce` |
| 4 | Verify desktop | Host userns setting for the sandbox; waits for XFCE on `:1`; checks Brave's sandbox |
| 5 | Desktop sudo | Toggles the declarative `desktop-nopasswd` group per `DESKTOP_SUDO` |
| 6 | Login and noVNC gateway | Creates the login, the loopback VNC proxy, and the gateway service |
| 7 | Resource limits | Container process limit and optional disk size |
| 8 | Docker checks | Build, Compose, and published-port test |
| 9 | Tailnet access (opt-in) | Tailscale `serve` (or `funnel`), only with `TAILSCALE=yes` |

## Layout

```
build.sh                 orchestrates the stages and shows progress
flake.nix / flake.lock   pins nixpkgs (nixos-26.05); exposes the image packages
nixos/                   the whole container, declaratively
  configuration.nix      top level; imports the LXC container module
  users.nix              desktop user, linger, the declarative sudo scaffold
  desktop.nix            XFCE, fonts, xfconf XML, dconf dock settings, autostart
  theme.nix              wires the theme packages; exposes the wallpaper path
  theme-pkgs/            WhiteSur gtk/icons/cursors + wallpaper derivations
  browser.nix            Brave with launch flags and managed policies
  vnc.nix                VNC and XFCE session as systemd user services
  docker.nix             nested Docker + Compose
  image-metadata.nix     the Incus metadata tarball
host/                    runs on the Ubuntu host (sudo)
  bootstrap-incus.sh     Incus, image import, container launch, UFW rules
  allow-userns.sh        host sysctl that lets Brave's sandbox start
  install-novnc.sh       noVNC login, VNC proxy device, gateway service
  install-tailscale.sh   tailnet/funnel publishing (replaces the quick tunnel)
  resource-policy.sh     container and gateway limits
  systemd/               the gateway unit
container/               pushed into the container and run there
  desktop-sudo.sh        DESKTOP_SUDO toggle (group membership only)
  docker-check.sh        Docker smoke tests
```

## Access and credentials

Open `http://127.0.0.1:6080/vnc.html`. The browser asks for the Basic-auth login:

- user: `desktop`
- password: `sudo grep NOVNC_AUTH /etc/xfce4-container/auth.env`

The VNC server inside the container has no password of its own. It listens only on
the container's loopback interface. Only the host's loopback proxy can reach it.
The login above is the only gate, so keep Funnel off unless you need public access.

## Notes

- **Same security trade-offs as the Ubuntu repo.** `host/allow-userns.sh` sets
  `kernel.apparmor_restrict_unprivileged_userns=0` on the host — a host-wide
  weakening of an Ubuntu hardening default. With `DESKTOP_SUDO=yes`, anything
  running as `desktop`, Brave included, can become root in the container; the
  container is still unprivileged.
- **No GPU passthrough.** The desktop renders in software (Mesa llvmpipe).
- **In-container NixOS, host stays Ubuntu.** The reproducibility win is the
  container; the thin host layer (Incus, websockify, noVNC, Tailscale) still comes
  from apt, and the README table above says exactly what floats.
- **Brave instead of Chrome.** For pinning reasons; its sandbox behaves the same
  way in the container, and stage 4 checks it starts.
- **Container cleanup:** `sudo incus delete xfce --force` removes the container.
  Then `sudo systemctl disable --now xfce-novnc` stops the gateway; delete the
  unit from `/etc/systemd/system/` too. Old images can pile up under the
  `xfce-nixos` alias after `nix flake update`; `sudo incus image list` and
  `sudo incus image delete <fingerprint>` prune them (the next build prunes
  unused ones itself).
