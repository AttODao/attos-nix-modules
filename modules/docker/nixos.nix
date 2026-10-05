{
  config,
  lib,
  pkgs,
  ...
}:
let
  latest = lib.filterAttrs (
    _: container: lib.hasSuffix ":latest" container.image
  ) config.virtualisation.oci-containers.containers;
in
{
  config = lib.mkIf config.modules.docker.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune = {
        enable = lib.mkDefault true;
        dates = lib.mkDefault "weekly";
      };
    };
    virtualisation.oci-containers.backend = lib.mkDefault "docker";
    assertions = lib.mapAttrsToList (name: container: {
      assertion = container.pull == "always";
      message = "OCI container '${name}' uses :latest and must set pull = \"always\".";
    }) latest;
    system.activationScripts.restartLatestOciContainers = {
      deps = [ "specialfs" ];
      text = lib.concatMapStringsSep "\n" (container: ''
        if ${pkgs.systemd}/bin/systemctl is-active --quiet ${lib.escapeShellArg container.serviceName} >/dev/null 2>&1; then
          ${pkgs.systemd}/bin/systemctl try-restart ${lib.escapeShellArg container.serviceName}
        fi
      '') (lib.attrValues latest);
    };
  };
}
