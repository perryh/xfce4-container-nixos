# The XFCE desktop itself: packages, fonts, per-channel xfconf defaults, the dconf
# settings for the Plank dock, the autostart entry, and the dock seeding script.
# The XML and CSS below are ported verbatim from the Ubuntu repo, with the browser
# and wallpaper paths pointed at their store locations.
{ config, lib, pkgs, ... }:

let
  # Minimal XFCE session: the set the Ubuntu repo's `xfce4` metapackage ended up
  # installing, minus Recommends. (These live at the top level in nixpkgs 26.05.)
  xfcePackages = [
    pkgs.xfce4-session
    pkgs.xfwm4
    pkgs.xfce4-panel
    pkgs.xfdesktop
    pkgs.xfce4-settings
    pkgs.thunar
    pkgs.xfce4-terminal
  ];

  # XFCE autostart: seed Plank's launchers for this HOME, then run the dock.
  # Dock settings (theme, item order) come from the system dconf database.
  desktop-dock = pkgs.writeShellScriptBin "desktop-dock" ''
    set -eu
    launchers="''${HOME}/.config/plank/dock1/launchers"
    mkdir -p "''${launchers}"

    write_item() {
      printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$2" >"''${launchers}/$1.dockitem"
    }
    write_item brave ${config.xfce4-container.browser}/share/applications/brave-browser.desktop
    write_item xfce4-terminal ${pkgs.xfce4-terminal}/share/applications/xfce4-terminal.desktop
    exec ${pkgs.plank}/bin/plank
  '';

  # Single translucent top bar (menu bar); the dock at the bottom is Plank.
  panelXML = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <channel name="xfce4-panel" version="1.0">
      <property name="configver" type="int" value="2"/>
      <property name="panels" type="array">
        <value type="int" value="1"/>
        <property name="dark-mode" type="bool" value="false"/>
        <property name="panel-1" type="empty">
          <property name="position" type="string" value="p=6;x=0;y=0"/>
          <property name="length" type="uint" value="100"/>
          <property name="position-locked" type="bool" value="true"/>
          <property name="size" type="uint" value="28"/>
          <property name="icon-size" type="uint" value="16"/>
          <property name="enter-opacity" type="uint" value="100"/>
          <property name="leave-opacity" type="uint" value="100"/>
          <property name="background-style" type="uint" value="1"/>
          <property name="background-rgba" type="array">
            <value type="double" value="0.97"/>
            <value type="double" value="0.97"/>
            <value type="double" value="0.98"/>
            <value type="double" value="0.72"/>
          </property>
          <property name="plugin-ids" type="array">
            <value type="int" value="1"/>
            <value type="int" value="2"/>
            <value type="int" value="3"/>
            <value type="int" value="4"/>
          </property>
        </property>
      </property>
      <property name="plugins" type="empty">
        <property name="plugin-1" type="string" value="applicationsmenu">
          <property name="button-icon" type="string" value="start-here"/>
          <property name="show-button-title" type="bool" value="false"/>
          <property name="show-generic-names" type="bool" value="false"/>
          <property name="show-tooltips" type="bool" value="false"/>
        </property>
        <property name="plugin-2" type="string" value="separator">
          <property name="expand" type="bool" value="true"/>
          <property name="style" type="uint" value="0"/>
        </property>
        <property name="plugin-3" type="string" value="systray">
          <property name="square-icons" type="bool" value="true"/>
        </property>
        <property name="plugin-4" type="string" value="clock">
          <property name="mode" type="uint" value="2"/>
          <property name="digital-layout" type="uint" value="3"/>
          <property name="digital-time-format" type="string" value="%a %b %-d  %-I:%M %p"/>
          <property name="digital-time-font" type="string" value="Inter Display SemiBold 10"/>
        </property>
      </property>
    </channel>
  '';
in
{
  environment.systemPackages = xfcePackages ++ [
    desktop-dock
    pkgs.plank
    pkgs.xdotool # handy for scripting the desktop, as in the Ubuntu repo
    pkgs.iproute2 # ss, used by the build's desktop checks
    pkgs.shadow # gpasswd/usermod, used by the DESKTOP_SUDO toggle
  ];

  # ---- fonts -----------------------------------------------------------------

  fonts.packages = [
    pkgs.inter
    pkgs.jetbrains-mono
    pkgs.noto-fonts-color-emoji
  ];

  # Ported from the Ubuntu repo's etc/fonts/local.conf. The fontconfig module
  # writes /etc/fonts/local.conf for us.
  fonts.fontconfig.localConf = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <alias>
        <family>sans-serif</family>
        <prefer><family>Inter</family><family>Noto Color Emoji</family></prefer>
      </alias>
      <alias>
        <family>system-ui</family>
        <prefer><family>Inter</family></prefer>
      </alias>
      <alias>
        <family>monospace</family>
        <prefer><family>JetBrains Mono</family><family>Noto Color Emoji</family></prefer>
      </alias>
      <match target="font">
        <edit name="antialias" mode="assign"><bool>true</bool></edit>
        <edit name="hinting" mode="assign"><bool>true</bool></edit>
        <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
        <edit name="rgba" mode="assign"><const>none</const></edit>
        <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
      </match>
    </fontconfig>
  '';

  # ---- Plank dock (system dconf database) -------------------------------------

  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "net/launchpad/plank/docks/dock1" = {
          dock-items = "['brave.dockitem', 'xfce4-terminal.dockitem']";
          theme = "'WhiteSur-Light'";
          icon-size = "48";
          zoom-enabled = "true";
          zoom-percent = "140";
          hide-mode = "0";
          position = "'bottom'";
          alignment = "'center'";
          show-dock-item = "false";
          lock-items = "true";
        };
      };
    }
  ];

  # ---- xfconf per-channel defaults ---------------------------------------------

  environment.etc."xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <channel name="xsettings" version="1.0">
      <property name="Net" type="empty">
        <property name="ThemeName" type="string" value="WhiteSur-Light"/>
        <property name="IconThemeName" type="string" value="WhiteSur-light"/>
        <property name="EnableEventSounds" type="bool" value="false"/>
        <property name="EnableInputFeedbackSounds" type="bool" value="false"/>
      </property>
      <property name="Xft" type="empty">
        <property name="Antialias" type="int" value="1"/>
        <property name="Hinting" type="int" value="1"/>
        <property name="HintStyle" type="string" value="hintslight"/>
        <property name="RGBA" type="string" value="none"/>
        <property name="DPI" type="int" value="96"/>
      </property>
      <property name="Gtk" type="empty">
        <property name="FontName" type="string" value="Inter 10"/>
        <property name="MonospaceFontName" type="string" value="JetBrains Mono 10"/>
        <property name="CursorThemeName" type="string" value="WhiteSur-cursors"/>
        <property name="CursorThemeSize" type="int" value="24"/>
        <property name="ButtonImages" type="bool" value="false"/>
        <property name="MenuImages" type="bool" value="false"/>
        <property name="DecorationLayout" type="string" value="close,minimize,maximize:"/>
      </property>
    </channel>
  '';

  environment.etc."xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <channel name="xfwm4" version="1.0">
      <property name="general" type="empty">
        <property name="theme" type="string" value="WhiteSur-Light"/>
        <property name="title_font" type="string" value="Inter Semi-Bold 10"/>
        <property name="title_alignment" type="string" value="center"/>
        <property name="button_layout" type="string" value="CHM|"/>
        <property name="use_compositing" type="bool" value="true"/>
        <property name="show_frame_shadow" type="bool" value="true"/>
        <property name="show_popup_shadow" type="bool" value="true"/>
        <property name="show_dock_shadow" type="bool" value="false"/>
        <property name="placement_mode" type="string" value="center"/>
        <property name="placement_ratio" type="int" value="100"/>
        <property name="workspace_count" type="int" value="1"/>
        <property name="cycle_preview" type="bool" value="true"/>
      </property>
    </channel>
  '';

  environment.etc."xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml".text = panelXML;

  # XFCE's "reset panel to default" reads this.
  environment.etc."xdg/xfce4/panel/default.xml".text = panelXML;

  # Catppuccin Mocha palette.
  environment.etc."xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <channel name="xfce4-terminal" version="1.0">
      <property name="font-name" type="string" value="JetBrains Mono 11"/>
      <property name="font-use-system" type="bool" value="false"/>
      <property name="misc-menubar-default" type="bool" value="false"/>
      <property name="misc-default-geometry" type="string" value="110x32"/>
      <property name="misc-cursor-shape" type="string" value="TERMINAL_CURSOR_SHAPE_IBEAM"/>
      <property name="misc-cursor-blinks" type="bool" value="true"/>
      <property name="misc-confirm-close" type="bool" value="false"/>
      <property name="misc-show-unsafe-paste-dialog" type="bool" value="false"/>
      <property name="scrolling-bar" type="string" value="TERMINAL_SCROLLBAR_NONE"/>
      <property name="color-use-theme" type="bool" value="false"/>
      <property name="color-foreground" type="string" value="#cdd6f4"/>
      <property name="color-background" type="string" value="#1e1e2e"/>
      <property name="color-cursor-use-default" type="bool" value="false"/>
      <property name="color-cursor" type="string" value="#f5e0dc"/>
      <property name="color-bold-use-default" type="bool" value="true"/>
      <property name="color-palette" type="string" value="#45475a;#f38ba8;#a6e3a1;#f9e2af;#89b4fa;#f5c2e7;#94e2d5;#bac2de;#585b70;#f38ba8;#a6e3a1;#f9e2af;#89b4fa;#f5c2e7;#94e2d5;#6aadc8"/>
    </channel>
  '';

  # Xtigervnc exposes a single monitor named VNC-0. The wallpaper is a store path.
  environment.etc."xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <channel name="xfce4-desktop" version="1.0">
      <property name="desktop-icons" type="empty">
        <property name="style" type="int" value="0"/>
      </property>
      <property name="desktop-menu" type="empty">
        <property name="show" type="bool" value="false"/>
      </property>
      <property name="backdrop" type="empty">
        <property name="screen0" type="empty">
          <property name="monitorVNC-0" type="empty">
            <property name="workspace0" type="empty">
              <property name="color-style" type="int" value="0"/>
              <property name="image-style" type="int" value="5"/>
              <property name="last-image" type="string" value="${config.xfce4-container.wallpaper}"/>
            </property>
          </property>
        </property>
      </property>
    </channel>
  '';

  environment.etc."xdg/xfce4/helpers.rc".text = ''
    WebBrowser=brave
    TerminalEmulator=xfce4-terminal
  '';

  # Translucent top bar: dark text, room at the edges; terminal padding.
  environment.etc."xdg/gtk-3.0/gtk.css".text = ''
    .xfce4-panel label {
      color: #1d1d1f;
    }

    .xfce4-panel button {
      padding-left: 12px;
      padding-right: 12px;
    }

    vte-terminal {
      padding: 10px 14px;
    }
  '';

  environment.etc."xdg/autostart/desktop-dock.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Dock
    Exec=${desktop-dock}/bin/desktop-dock
    OnlyShowIn=XFCE;
    NoDisplay=true
    X-XFCE-Autostart-Override=true
  '';
}
