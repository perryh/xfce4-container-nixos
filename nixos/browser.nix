# Brave, pinned exactly by flake.lock (nixpkgs fetches a specific release tarball
# with a hash — unlike Google Chrome, which only publishes "current"). The wrapper
# carries the same launch flags the Ubuntu repo passed through its google-chrome
# wrapper, so every launch path (PATH, menus, dock) goes through it.
{ config, lib, pkgs, ... }:

let
  brave = pkgs.brave.override {
    commandLineArgs = [
      "--disable-dev-shm-usage"
      "--no-first-run"
      "--no-default-browser-check"
      "--password-store=basic"
    ];
  };
in
{
  options.xfce4-container.browser = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    description = "The wrapped Brave, referenced by the dock and helpers config.";
  };

  config = {
    xfce4-container.browser = brave;

    environment.systemPackages = [ brave ];

    # Managed policies; Brave reads Chromium policies from /etc/brave.
    environment.etc."brave/policies/managed/desktop.json".text = ''
      {
        "CommandLineFlagSecurityWarningsEnabled": false,
        "DefaultBrowserSettingEnabled": false,
        "PromotionalTabsEnabled": false,
        "MetricsReportingEnabled": false
      }
    '';
  };
}
