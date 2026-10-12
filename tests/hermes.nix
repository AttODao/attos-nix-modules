{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  evaluate =
    modules:
    (t.evalSystem {
      users = [ ];
      inherit modules;
    }).config;
  base = evaluate [ ];
  input = {
    dataDir = "/srv/hermes";
    uid = 1100;
    gid = 1100;
  };
  owner = {
    networking.hostName = "agent";
    modules.swarm = {
      role = "manager";
      advertiseAddress = "10.250.0.2";
    };
    modules.public-services."hermes.example.test".hermes = input // {
      enable = true;
      host = "agent";
    };
  };
  local = evaluate [ owner ];
  container = local.virtualisation.oci-containers.containers.hermes;
  standalone = evaluate [
    {
      modules.hermes = input // {
        enable = true;
      };
    }
  ];
  remote = evaluate [
    {
      modules.public-services."hermes.example.test".hermes = {
        enable = true;
        host = "elsewhere";
      };
    }
  ];
  external = evaluate [
    {
      modules.public-services."hermes.example.test".hermes = {
        enable = true;
        host = "elsewhere";
        deploy = false;
        backendUrl = "http://external:9119";
      };
    }
  ];
  disabled = evaluate [
    {
      modules.public-services."hermes.example.test".hermes.host = "agent";
    }
  ];
  ps = import ../modules/public-services/lib.nix { inherit lib; };
  missing = builtins.tryEval (
    builtins.deepSeq
      (evaluate [
        {
          modules.hermes.enable = true;
        }
      ]).virtualisation.oci-containers.containers.hermes.volumes
      true
  );
  duplicate = evaluate [
    owner
    {
      modules.public-services."other.example.test".hermes = input // {
        enable = true;
        host = "agent";
      };
    }
  ];
  both = evaluate [
    owner
    {
      modules.hermes = input // {
        enable = true;
      };
    }
  ];
  public = evaluate [
    owner
    { modules.public-services."hermes.example.test".hermes.private = false; }
  ];
  rootUser =
    builtins.tryEval
      (evaluate [
        {
          modules.hermes = input // {
            enable = true;
            uid = 0;
          };
        }
      ]).virtualisation.oci-containers.containers.hermes.environment.HERMES_UID;
  valid = c: lib.all (a: a.assertion) c.assertions;
  absent =
    c:
    !(c.virtualisation.oci-containers.containers ? hermes)
    && !(c.systemd.services ? docker-hermes)
    && !c.modules.docker.enable
    && !c.modules.swarm.enable;
in
assert absent base && absent remote && absent external && absent disabled;
assert !base.modules.hermes.enable;
assert valid local && valid standalone && valid remote && valid external;
assert !valid duplicate && !valid both && !valid public;
assert !missing.success && !rootUser.success;
assert local.modules.public-services."hermes.example.test".hermes.private;
assert local.modules.docker.enable && local.modules.swarm.enable;
assert container.ports == [ ];
assert container.user == null;
assert container.environment.HERMES_UID == "1100" && container.environment.HERMES_GID == "1100";
assert container.entrypoint == null;
assert !(container.environment ? HERMES_DASHBOARD);
assert !lib.elem "--init" container.extraOptions;
assert lib.hasSuffix "@sha256:9774f4f39a9bb8c2f68ce728ed5e99ddbad282163be56764afacf88ed952b784"
  container.image;
assert container.networks == [ "backend-hermes" ];
assert container.volumes == [ "/srv/hermes:/opt/data" ];
assert container.environment.HERMES_HOME == "/opt/data";
assert container.environment.HOME == "/opt/data";
assert !(container.environment ? HERMES_DASHBOARD_BASIC_AUTH_PASSWORD);
assert container.environmentFiles == [ ];
assert lib.elem "--cap-drop=ALL" container.extraOptions;
assert lib.elem "--security-opt=no-new-privileges:true" container.extraOptions;
assert lib.all (p: !(lib.hasInfix "docker.sock" p)) container.volumes;
assert
  container.cmd == [
    "dashboard"
    "--host"
    "0.0.0.0"
    "--port"
    "9119"
    "--no-open"
  ];
assert local.systemd.services.docker-hermes.unitConfig.RequiresMountsFor == [ "/srv/hermes" ];
assert
  local.systemd.services.docker-hermes.unitConfig.ConditionPathExists == [
    "/srv/hermes/config.yaml"
    "/srv/hermes/.env"
  ];
assert !(local.environment.etc ? "hermes/config.yaml");
assert !(local.system.activationScripts ? hermes);
assert (builtins.head (ps.routes local)).cfg.backendUrl == "http://hermes:9119";
assert ps.backendNetworks local == [ "backend-hermes" ];
assert ps.routes standalone == [ ];
assert standalone.modules.public-services == { };
assert
  !standalone.modules.swarm.enable
  && !standalone.modules.traefik.enable
  && !standalone.modules.dns.enable;
assert
  standalone.virtualisation.oci-containers.containers.hermes.ports == [ "127.0.0.1:9119:9119" ];
assert standalone.virtualisation.oci-containers.containers.hermes.networks == [ "local-services" ];
assert ps.backendNetworks external == [ ];
true
