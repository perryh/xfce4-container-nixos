# The macOS-style look: WhiteSur GTK/icons/cursors (pinned by rev+hash, see
# theme-pkgs/) and the generated wallpaper. Exposes the wallpaper path as an
# option so desktop.nix can reference it from the xfconf XML.
{ config, lib, pkgs, ... }:

{
  options.xfce4-container.wallpaper = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    description = "The generated gradient wallpaper, referenced by the desktop XML.";
  };

  config = {
    xfce4-container.wallpaper = pkgs.callPackage ./theme-pkgs/wallpaper.nix { };

    environment.systemPackages = [
      (pkgs.callPackage ./theme-pkgs/whitesur-gtk.nix { })
      (pkgs.callPackage ./theme-pkgs/whitesur-icons.nix { })
      (pkgs.callPackage ./theme-pkgs/whitesur-cursors.nix { })
    ];
  };
}
