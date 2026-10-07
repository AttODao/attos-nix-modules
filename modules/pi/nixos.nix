{
  config,
  lib,
  attopkgs,
  ...
}:
{
  config = lib.mkIf (config.modules.pi.enable && config.modules.pi.systemWide) {
    environment.systemPackages = [
      attopkgs.pi
      attopkgs.context-mode
    ];
  };
}
