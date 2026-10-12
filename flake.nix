{
  description = "Reproducible XFCE desktop in an Incus container (NixOS 26.05), reached through noVNC";

  # Pinned to the current stable branch. flake.lock freezes the exact commit, so the
  # same checkout builds the same desktop on any machine, on any date. To move to a
  # new stable release (26.05 is supported until 2026-12-31), change this URL and
  # run `nix flake update`.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.xfce = nixpkgs.lib.nixosSystem {
        modules = [
          { nixpkgs.hostPlatform = system; }
          ./nixos/configuration.nix
        ];
      };

      packages.${system} = {
        # Split image for `incus image import`: LXC rootfs tarball + metadata tarball.
        rootfs = self.nixosConfigurations.xfce.config.system.build.tarball;
        metadata = pkgs.callPackage ./nixos/image-metadata.nix { };

        # Exposed for inspection/testing; the container only needs the two above.
        whitesur-gtk = pkgs.callPackage ./nixos/theme-pkgs/whitesur-gtk.nix { };
        whitesur-icons = pkgs.callPackage ./nixos/theme-pkgs/whitesur-icons.nix { };
        whitesur-cursors = pkgs.callPackage ./nixos/theme-pkgs/whitesur-cursors.nix { };
        wallpaper = pkgs.callPackage ./nixos/theme-pkgs/wallpaper.nix { };

        default = self.packages.${system}.rootfs;
      };
    };
}
