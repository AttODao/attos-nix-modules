{ config, lib, ... }:
{
  config = lib.mkIf config.modules.solaar.enable {
    programs.solaar.enable = true;
  };
}
