# The VNC display and the XFCE session on it, as systemd user units of the desktop
# user (started at boot via linger). Ported from the Ubuntu repo's user units:
# TigerVNC on :1, loopback only, no VNC password — the host's loopback proxy is the
# only client that can reach it.
{ config, lib, pkgs, ... }:

let
  # Everything the session spawns is in the system path; keep unit PATHs tight.
  sw-bin = "/run/current-system/sw/bin";
in
{
  systemd.user.services.xfce-vnc = {
    description = "TigerVNC display :1 for the XFCE desktop (loopback only)";
    wantedBy = [ "default.target" ];

    environment = {
      DISPLAY = ":1";
      # The systemd user manager sets its own PATH by default; ours is a superset
      # (the system path carries coreutils, grep, sed, systemctl, and the desktop).
      PATH = lib.mkForce "${sw-bin}";
    };

    serviceConfig = {
      Type = "simple";
      ExecStartPre = "-${pkgs.coreutils}/bin/rm -f /tmp/.X1-lock /tmp/.X11-unix/X1";
      ExecStart = "${pkgs.tigervnc}/bin/Xvnc :1 -geometry 1920x1200 -depth 24 -localhost -rfbport 5901 -SecurityTypes None -AlwaysShared -desktop xfce";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };

  systemd.user.services.xfce-session = {
    description = "XFCE session on display :1";
    wantedBy = [ "default.target" ];
    requires = [ "xfce-vnc.service" ];
    after = [ "xfce-vnc.service" ];

    environment = {
      DISPLAY = ":1";
      XDG_SESSION_TYPE = "x11";
      XDG_CURRENT_DESKTOP = "XFCE";
      XDG_DATA_DIRS = "/run/current-system/sw/share";
      PATH = lib.mkForce "${sw-bin}";
    };

    serviceConfig = {
      Type = "simple";
      ExecStartPre = ''
        ${pkgs.bash}/bin/bash -c 'for i in $(seq 1 20); do [ -S /tmp/.X11-unix/X1 ] && exit 0; sleep 1; done; exit 1'
      '';
      ExecStart = "${pkgs.dbus}/bin/dbus-run-session -- ${pkgs.xfce4-session}/bin/startxfce4";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
