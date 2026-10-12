# NixOS configuration for the desktop container. Everything inside the container is
# declared here and in the modules it imports; there are no imperative setup steps.
# build.sh builds this into an LXC rootfs tarball (system.build.tarball from the
# lxc-container module) and imports it into Incus on the host.
{ lib, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
    ./users.nix
    ./desktop.nix
    ./theme.nix
    ./browser.nix
    ./vnc.nix
    ./docker.nix
  ];

  # The container is driven through `incus exec` and the VNC session; no sshd.
  # (The lxc-container module defaults to on-demand ssh; we do not need it.)
  services.openssh.enable = false;

  networking.hostName = "xfce";

  # DHCP on the Incus veth; the lxc-container module wires systemd-networkd for it.
  networking.useDHCP = true;

  i18n.defaultLocale = "en_US.UTF-8";

  documentation.enable = false; # keeps the image small

  system.stateVersion = "26.05";
}
