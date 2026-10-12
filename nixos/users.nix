# The desktop user and the declarative sudo scaffold. build.sh toggles membership
# in desktop-nopasswd from the outside (DESKTOP_SUDO=yes) with gpasswd; the rule
# itself lives here, so the toggle cannot introduce anything undeclared.
{ lib, ... }:

{
  users.users.desktop = {
    isNormalUser = true;
    description = "Desktop";
    # No password and no login session: the desktop is reached through VNC only.
    # Linger starts the user manager at boot; the VNC and session units run under it.
    linger = true;
  };

  # Anything running as desktop can become root in the container while it is a
  # member of this group. The container itself stays unprivileged.
  users.groups.desktop-nopasswd = { };

  security.sudo.enable = true;
  security.sudo.extraRules = [
    {
      groups = [ "desktop-nopasswd" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
