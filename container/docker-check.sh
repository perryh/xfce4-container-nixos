#!/usr/bin/env bash
# Docker checks inside the container. Run as root; build.sh pushes and runs it.
# Covers hello-world, a multi-layer build, and a Compose app with a published port.
set -euo pipefail

# incus exec does not give the shell the system path.
export PATH=/run/current-system/sw/bin:$PATH

PORT=8080

# docker.service is enabled declaratively (nixos/docker.nix); make sure it is up.
systemctl start docker.service
for _ in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 1
done
docker info >/dev/null 2>&1 || { echo "The docker daemon did not come up." >&2; exit 1; }

docker run --rm hello-world
docker compose version
docker info | grep -i "Storage Driver"

WORK=$(mktemp -d)
trap 'docker compose -f "$WORK/compose.yaml" down >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

cat >"$WORK/Dockerfile" <<'DOCKERFILE'
FROM alpine:3.20
RUN echo layer-one > /a
RUN echo layer-two > /b
RUN echo layer-three > /c
CMD ["cat", "/a", "/b", "/c"]
DOCKERFILE

docker build -t xfce4-container-build-test "$WORK"
docker run --rm xfce4-container-build-test

cat >"$WORK/compose.yaml" <<COMPOSE
services:
  web:
    image: nginx:alpine
    ports:
      - "$PORT:80"
COMPOSE

docker compose -f "$WORK/compose.yaml" up -d

open=""
for _ in $(seq 1 30); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
        open=yes
        break
    fi
    sleep 1
done

if [ "$open" != "yes" ]; then
    echo "FAIL: published port $PORT did not accept connections" >&2
    exit 1
fi
echo "OK: Docker build, Compose, and published port $PORT all work"
