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
    ]
    ++ lib.optional config.modules.pi.plugins.context-mode.enable attopkgs.context-mode;
  };
}
