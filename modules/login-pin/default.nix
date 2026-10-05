{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.login-pin.enable = lib.mkEnableOption "6-digit PIN authentication for attodao on greetd and TTY login";

  config = lib.mkIf config.modules.login-pin.enable {
  };
}
