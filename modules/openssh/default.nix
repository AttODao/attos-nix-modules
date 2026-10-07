{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.modules.openssh;
  # 未指定の公開入力でcontainer等のnative既定値を置き換えない。
  supplied = name: options.modules.openssh.${name}.highestPrio < (lib.mkOptionDefault null).priority;
in
{
  options.modules.openssh = {
    enable = lib.mkEnableOption "shared OpenSSH server support";
    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "sshd_config settings in native services.openssh.settings shape; unspecified keys keep their native defaults.";
    };
    listenAddresses = lib.mkOption {
      type = options.services.openssh.listenAddresses.type;
      default = config.services.openssh.listenAddresses;
      defaultText = lib.literalExpression "services.openssh.listenAddresses (normally [])";
      description = "Listen addresses in native { addr; port ? null; } shape; an empty list keeps native all-address listening.";
    };
    startWhenNeeded = lib.mkOption {
      type = lib.types.bool;
      default = config.services.openssh.startWhenNeeded;
      defaultText = lib.literalExpression "services.openssh.startWhenNeeded (normally false)";
      description = "Use socket activation instead of a persistent sshd.";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = config.services.openssh.openFirewall;
      defaultText = lib.literalExpression "services.openssh.openFirewall (normally true)";
      description = "Open the native OpenSSH ports in the firewall.";
    };
    waitForNetwork = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Order the sshd listener after network-online.target and pull that target in, for addresses configured during boot.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings = lib.mapAttrs (_: lib.mkDefault) cfg.settings;
      listenAddresses = lib.mkIf (supplied "listenAddresses") cfg.listenAddresses;
      startWhenNeeded = lib.mkIf (supplied "startWhenNeeded") cfg.startWhenNeeded;
      openFirewall = lib.mkIf (supplied "openFirewall") cfg.openFirewall;
    };
    systemd = lib.mkIf cfg.waitForNetwork (
      if config.services.openssh.startWhenNeeded then
        {
          sockets.sshd = {
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
          };
        }
      else
        {
          services.sshd = {
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
          };
        }
    );
  };
}
