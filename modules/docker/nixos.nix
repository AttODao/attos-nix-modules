{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = config.modules.docker;
  # Per-service bridges (backend-<service>) shared by a service's containers and same-host clients.
  serviceBridges = lib.unique (
    lib.filter (lib.hasPrefix "backend-") (
      lib.concatMap (container: map networkName container.networks) (
        lib.attrValues config.virtualisation.oci-containers.containers
      )
    )
  );
  latest = lib.filterAttrs (
    _: container: lib.hasSuffix ":latest" container.image
  ) config.virtualisation.oci-containers.containers;
  # Container network entries may carry attachment options: "name=<net>,ip=...".
  networkName = entry: lib.removePrefix "name=" (builtins.head (lib.splitString "," entry));
  ensureNetwork =
    name: network:
    lib.escapeShellArgs (
      [
        "${attopkgs.attos-docker}/bin/attos-docker"
        "network"
        "ensure"
        "--docker"
        "${config.virtualisation.docker.package}/bin/docker"
        "--name"
        name
      ]
      ++ lib.optionals (network.subnet != null) [
        "--subnet"
        network.subnet
      ]
      ++ lib.optionals (network.gateway != null) [
        "--gateway"
        network.gateway
      ]
      ++ lib.concatLists (
        lib.mapAttrsToList (key: value: [
          "--opt"
          "${key}=${value}"
        ]) network.options
      )
    );
  bridgesOf =
    container: lib.filter (name: cfg.networks ? ${name}) (map networkName container.networks);
  bridgeContainers = lib.filterAttrs (
    _: container: bridgesOf container != [ ]
  ) config.virtualisation.oci-containers.containers;
in
{
  config = lib.mkIf cfg.enable {
    assertions =
      lib.mapAttrsToList (name: network: {
        assertion =
          builtins.match "[a-zA-Z0-9][a-zA-Z0-9_.-]*" name != null
          && (network.gateway == null || network.subnet != null);
        message = "modules.docker.networks.${name}: invalid network name, or gateway without subnet.";
      }) cfg.networks
      ++ lib.mapAttrsToList (name: container: {
        assertion = container.pull == "always";
        message = "OCI container '${name}' uses :latest and must set pull = \"always\".";
      }) latest;
    virtualisation.docker = {
      enable = true;
      autoPrune = {
        enable = lib.mkDefault true;
        dates = lib.mkDefault "weekly";
      };
    };
    virtualisation.oci-containers.backend = lib.mkDefault "docker";
    modules.docker.networks = lib.genAttrs serviceBridges (_: { });
    systemd.services = lib.mkMerge [
      (lib.mapAttrs' (
        name: network:
        lib.nameValuePair "docker-network-${name}" {
          description = lib.mkDefault "Ensure Docker network ${name}";
          wantedBy = [ "multi-user.target" ];
          requires = [ "docker.service" ];
          after = [
            "docker.service"
            "docker.socket"
          ];
          serviceConfig = {
            Type = lib.mkDefault "oneshot";
            RemainAfterExit = lib.mkDefault true;
            ExecStart = ensureNetwork name network;
          };
        }
      ) cfg.networks)
      (lib.mapAttrs' (
        name: container:
        let
          bridges = bridgesOf container;
          units = map (network: "docker-network-${network}.service") bridges;
        in
        lib.nameValuePair container.serviceName {
          requires = units;
          after = units;
          # The persistent oneshot can stay active after Docker prune removes an
          # unused bridge, so recheck actual Docker state before every start.
          preStart = lib.mkBefore (
            lib.concatMapStringsSep "\n" (network: ensureNetwork network cfg.networks.${network}) bridges
          );
        }
      ) bridgeContainers)
    ];
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
