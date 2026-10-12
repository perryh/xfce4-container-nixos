# Incus/LXD image metadata tarball. The creation date is a fixed constant so the
# tarball — and therefore the Incus fingerprint — is stable for a given flake.
{ runCommand }:

runCommand "nixos-xfce-lxc-metadata" { } ''
  mkdir -p $out
  cat > metadata.yaml <<'YAML'
  architecture: x86_64
  creation_date: 1767225600
  properties:
    description: NixOS 26.05 XFCE desktop (xfce4-container-nixos)
    os: nixos
    release: 26.05
    variant: xfce-desktop
  YAML
  tar --format=gnu --mtime='@1767225600' --owner=0 --group=0 --numeric-owner \
      -czf $out/metadata.tar.gz metadata.yaml
''
