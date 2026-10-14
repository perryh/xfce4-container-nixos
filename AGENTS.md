# AGENTS.md

A reproducible XFCE desktop in an Incus container: same architecture as the sibling
Ubuntu repo (`../xfce4-container`), but the container is NixOS 26.05 built from the
locked flake. Runs on an Ubuntu host; the browser reaches the desktop through noVNC
on the host's loopback (127.0.0.1:6080, Basic-auth).

## Where things run

- `nixos/` — the entire container, declaratively. `flake.nix` + `flake.lock` pin
  nixpkgs stable (`nixos-26.05`). Never make in-container changes imperative;
  everything (packages, config, units, theme) belongs in a module here.
- `host/` — bash + apt, runs with sudo on the Ubuntu host. Scripts must stay
  idempotent: every step checks its own state so `./build.sh` is re-runnable.
- `container/` — small scripts build.sh pushes into the container with
  `incus file push` and runs (sudo toggle, docker checks).
- `build.sh` — orchestrator. Env toggles: `DESKTOP_SUDO`, `TAILSCALE`, `FUNNEL`,
  `RECREATE` (recreate the container after an image change; resets /home/desktop),
  `CT` (default `xfce`).

## Validating changes

On the NixOS dev machine, the flake side is fully testable (host is on the same
channel, so the binary cache covers most of the closure):

```bash
nix --extra-experimental-features 'nix-command flakes' build \
    .#rootfs .#metadata .#whitesur-gtk .#whitesur-icons .#whitesur-cursors .#wallpaper
bash -n build.sh host/*.sh container/*.sh
```

`.#rootfs` exercises eval, all modules, and the tarball — treat a green build as the
minimum bar for any change. Inspect built outputs (unit files, /etc tree) via
`nix build ... --print-out-paths` and looking inside, or through the system closure's
`etc/`. The host scripts and the full `./build.sh` can only be tested on the Ubuntu
target with sudo; do not run `build.sh` on the dev machine (it will fail at apt).

## Conventions and gotchas

- **Everything in the container is declarative.** If a change needs a command run
  inside the running container, it belongs in a NixOS module instead, or (for a
  runtime toggle like DESKTOP_SUDO) as a declarative scaffold plus a tiny
  membership/property flip.
- **Porting from the Ubuntu repo:** config files under its `container/config/` map
  to `environment.etc` entries (mind owners/symlinks); the chrome wrapper's flags
  went into `pkgs.brave.override { commandLineArgs }`; theme installs became the
  derivations in `nixos/theme-pkgs/`.
- **Pinned sources:** `fetchFromGitHub` with immutable commit revs (not tags) and
  SRI hashes. To fix a hash mismatch, put a dummy `hash` and copy the `got:` value
  from the error. The hash covers the extracted tree, not the tarball bytes.
- **stdenv exports `$name`** into builds; upstream install scripts that use a
  lowercase `name` variable will pick it up (this bit WhiteSur's icon install —
  hence the explicit `-n WhiteSur`).
- **No `/usr` inside the container.** In-container commands from outside use
  absolute paths under `/run/current-system/sw/bin` (see `CTBIN` in build.sh), or
  `/bin/sh`. Scripts pushed into the container set
  `export PATH=/run/current-system/sw/bin:$PATH`.
- **systemd user units** set `PATH` with `lib.mkForce`; the NixOS user manager
  defines a default PATH, so plain assignments conflict at eval.
- **NixOS 26.05 renames seen here:** `noto-color-emoji` → `noto-fonts-color-emoji`;
  `xfce.*` packages moved to top level (`pkgs.xfce4-panel`, `pkgs.thunar`, ...).
- **Security invariants — do not loosen:** VNC and the gateway listen on loopback
  only (`check_loopback` in build.sh fails the build otherwise); the VNC server has
  no password by design because only the host proxy can reach it; the Basic-auth
  login is the only gate. The userns sysctl (`host/allow-userns.sh`) is a known,
  documented host-wide weakening.

## Version bumps

`nix flake update` (or a new `nixpkgs.url` release branch) changes the image; a
running container then needs `RECREATE=yes ./build.sh`. 26.05 is supported until
2026-12-31 — after that, move to the next stable branch in `flake.nix` and update
the lock. Commit `flake.lock` changes together with anything that depends on them.
