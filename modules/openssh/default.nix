{ config, lib, ... }:
{
  options.modules.openssh.enable = lib.mkEnableOption "shared OpenSSH server support";
  config = lib.mkIf config.modules.openssh.enable {
    services.openssh.enable = true;
  };
}
