{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = config.modules.bot-screen-host;
in
{
  options.modules.bot-screen-host = {
    enable = lib.mkEnableOption "packages for hosting a Hermes Bot Screen on this machine for a Hermes whose SSH terminal backend points here (TigerVNC Xvnc + Xfce core, cua-driver, VirtualGL, DejaVu and Noto CJK fonts)";
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      readOnly = true;
      internal = true;
      description = "Binaries the Hermes Bot Screen launcher and computer_use look up on PATH.";
      # Bot ScreenのlauncherはgatewayのPATHとSSHのlogin shellの両方でこれらを使う。
      # VirtualGLはGLのappをGPUで描画してXvncへ出すために使う。
      default = with pkgs; [
        tigervnc
        xfwm4
        xfce4-panel
        xfdesktop
        xfce4-settings
        xfce4-terminal
        dbus
        xauth
        xdpyinfo
        setxkbmap
        xprop
        xsetroot
        xset
        at-spi2-core
        attopkgs.cua-driver
        attopkgs.virtualgl
      ];
    };
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = cfg.packages;
    # Bot ScreenのXfce・appが日本語localeで豆腐にならないように。
    fonts.packages = [
      pkgs.dejavu_fonts
      pkgs.noto-fonts-cjk-sans
    ];
  };
}
