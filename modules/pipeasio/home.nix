{
  osConfig,
  lib,
  attopkgs,
  ...
}:
let
  register = attopkgs.pipeasio-steam-prefixes;
in
{
  config = lib.mkIf osConfig.modules.pipeasio.enable {
    # Existing Proton prefixes need registry entries that package installation cannot create.
    home.packages = [ register ];

    # Registration runs once per user session instead of on every HM activation.
    systemd.user.services.pipeasio-register-steam-prefixes = {
      Unit = {
        Description = "Register PipeASIO in existing Steam Proton prefixes";
        ConditionPathExists = "%h/.local/share/Steam/steamapps";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe register} --skip-registered --no-runtime-download";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
