{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  cfg =
    modules:
    (t.evalSystem {
      users = [ ];
      inherit modules;
    }).config;
  accounts = {
    users.groups.mcsm = { };
    users.users.mcsm-web = {
      isSystemUser = true;
      group = "mcsm";
    };
    users.users.mcsm-daemon = {
      isSystemUser = true;
      group = "mcsm";
    };
  };
  input = {
    enable = true;
    dataDir = "/srv/mcsmanager";
    webUser = "mcsm-web";
    daemonUser = "mcsm-daemon";
    group = "mcsm";
    daemonKeyFile = "/run/secrets/mcsmanager-key";
  };
  record = input // {
    host = "nixos";
    backendUrl = "http://10.250.0.1:23333";
    daemonBackendUrl = "http://10.250.0.1:24444";
    listenAddress = "10.250.0.1";
    backendAddress = "10.250.0.1";
    tcpPorts = [ 25565 ];
    udpPorts = [ 19132 ];
  };
  public = cfg [
    accounts
    { modules.public-services."mine.example.test".mcsmanager = record; }
  ];
  standalone = cfg [
    accounts
    { modules.mcsmanager = input; }
  ];
  base = cfg [ ];
  remote = cfg [
    {
      modules.public-services."mine.example.test".mcsmanager = {
        enable = true;
        host = "other";
      };
    }
  ];
  external = cfg [
    {
      modules.public-services."mine.example.test".mcsmanager = {
        enable = true;
        host = "nixos";
        deploy = false;
        backendUrl = "http://external.example.test:23333";
        daemonBackendUrl = "http://external.example.test:24444";
      };
    }
  ];
  disabled = cfg [ { modules.public-services."mine.example.test".mcsmanager.host = "nixos"; } ];
  overridden = cfg [
    accounts
    {
      modules.mcsmanager = input // {
        webPort = 23400;
        daemonPort = 24500;
        initialAdminFile = "/run/secrets/admin.json";
      };
      systemd.services.mcsmanager-daemon.serviceConfig.TimeoutStopSec = "5min";
    }
  ];
  visible = cfg [
    accounts
    {
      modules.public-services."mine.example.test".mcsmanager = record // {
        private = false;
      };
    }
  ];
  conflict = cfg [
    accounts
    {
      modules.mcsmanager = input;
      modules.public-services."mine.example.test".mcsmanager = record;
    }
  ];
  multiple = cfg [
    accounts
    {
      modules.public-services."mine.example.test".mcsmanager = record;
      modules.public-services."mine2.example.test".mcsmanager = record;
    }
  ];
  rootUser = cfg [
    accounts
    {
      modules.mcsmanager = input // {
        daemonUser = "root";
      };
    }
  ];
  dockerUser = cfg [
    accounts
    {
      modules.mcsmanager = input;
      users.users.mcsm-daemon.extraGroups = [ "docker" ];
    }
  ];
  sameUser = cfg [
    accounts
    {
      modules.mcsmanager = input // {
        webUser = "mcsm-daemon";
      };
    }
  ];
  actualDockerUser = cfg [
    accounts
    {
      modules.mcsmanager = input;
      users.users.docker-operator = {
        isSystemUser = true;
        group = "mcsm";
        extraGroups = [ "docker" ];
      };
      systemd.services.mcsmanager-daemon.serviceConfig.User = "docker-operator";
    }
  ];
  actualDockerGroup = cfg [
    accounts
    {
      modules.mcsmanager = input;
      systemd.services.mcsmanager-daemon.serviceConfig.Group = "docker";
    }
  ];
  actualSameUser = cfg [
    accounts
    {
      modules.mcsmanager = input;
      systemd.services.mcsmanager-web.serviceConfig.User = "mcsm-daemon";
    }
  ];
  portCollision = cfg [
    accounts
    {
      modules.mcsmanager = input // {
        tcpPorts = [ 24444 ];
      };
    }
  ];
  valid = c: lib.all (a: a.assertion) c.assertions;
  absent =
    c:
    !(c.systemd.services ? mcsmanager-web)
    && !(c.systemd.services ? mcsmanager-daemon)
    && !c.modules.docker.enable
    && !c.modules.swarm.enable
    && !c.modules.traefik.enable;
  hardened =
    c:
    lib.all
      (
        name:
        let
          unit = c.systemd.services.${name}.serviceConfig;
        in
        unit.User != "root"
        && unit.NoNewPrivileges
        && unit.ProtectSystem == "strict"
        && unit.ProtectHome
        && unit.PrivateTmp
        && unit.CapabilityBoundingSet == [ ]
        && unit.UMask == "0077"
        && lib.elem "-/run/docker.sock" unit.InaccessiblePaths
        && lib.hasInfix "daemon-key:/run/secrets/mcsmanager-key" (builtins.toJSON unit.LoadCredential)
      )
      [
        "mcsmanager-web"
        "mcsmanager-daemon"
      ];
  missing =
    field:
    let
      c = cfg [
        accounts
        { modules.mcsmanager = builtins.removeAttrs input [ field ]; }
      ];
    in
    builtins.tryEval (
      builtins.deepSeq [
        c.systemd.services.mcsmanager-web.serviceConfig
        c.systemd.services.mcsmanager-daemon.serviceConfig
      ] true
    );
  badPath =
    builtins.tryEval
      (cfg [ { modules.mcsmanager.daemonKeyFile = /tmp; } ]).modules.mcsmanager.daemonKeyFile;
  badStore =
    builtins.tryEval
      (cfg [ { modules.mcsmanager.daemonKeyFile = "/nix/store/secret"; } ])
      .modules.mcsmanager.daemonKeyFile;
  badPort =
    builtins.tryEval
      (cfg [ { modules.mcsmanager.webPort = 70000; } ]).modules.mcsmanager.webPort;
in
assert valid base && absent base && !base.modules.mcsmanager.enable;
assert
  valid remote
  && absent remote
  && valid external
  && absent external
  && valid disabled
  && absent disabled;
assert valid public && hardened public && valid standalone && hardened standalone;
assert
  !public.modules.docker.enable && !public.modules.swarm.enable && !public.modules.traefik.enable;
assert
  public.virtualisation.oci-containers.containers == { }
  && standalone.virtualisation.oci-containers.containers == { };
assert standalone.modules.public-services == { };
assert public.modules.public-services."mine.example.test".mcsmanager.private;
assert public.modules.public-services."mine.example.test".mcsmanager.tcpPorts == [ 25565 ];
assert public.modules.public-services."mine.example.test".mcsmanager.udpPorts == [ 19132 ];
assert
  visible.modules.public-services."mine.example.test".mcsmanager.tcpPorts
  == public.modules.public-services."mine.example.test".mcsmanager.tcpPorts;
assert
  visible.modules.public-services."mine.example.test".mcsmanager.udpPorts
  == public.modules.public-services."mine.example.test".mcsmanager.udpPorts;
assert
  public.networking.firewall.allowedTCPPorts == [ ]
  && public.networking.firewall.allowedUDPPorts == [ ];
assert
  standalone.modules.mcsmanager.webPort == 23333 && standalone.modules.mcsmanager.daemonPort == 24444;
assert standalone.systemd.services.mcsmanager-web.serviceConfig.User == "mcsm-web";
assert standalone.systemd.services.mcsmanager-daemon.serviceConfig.User == "mcsm-daemon";
assert lib.hasInfix "share/mcsmanager/daemon/app.js"
  standalone.systemd.services.mcsmanager-daemon.serviceConfig.ExecStart;
assert
  standalone.systemd.services.mcsmanager-web.serviceConfig.ReadWritePaths
  == [ "/srv/mcsmanager/web" ];
assert
  standalone.systemd.services.mcsmanager-daemon.serviceConfig.ReadWritePaths
  == [ "/srv/mcsmanager/daemon" ];
assert overridden.systemd.services.mcsmanager-daemon.serviceConfig.TimeoutStopSec == "5min";
assert lib.elem "initial-admin:/run/secrets/admin.json"
  overridden.systemd.services.mcsmanager-web.serviceConfig.LoadCredential;
assert
  !valid conflict
  && !valid multiple
  && !valid rootUser
  && !valid dockerUser
  && !valid sameUser
  && !valid actualDockerUser
  && !valid actualDockerGroup
  && !valid actualSameUser
  && !valid portCollision;
assert !badPath.success && !badStore.success && !badPort.success;
assert lib.all (field: !(missing field).success) [
  "dataDir"
  "daemonKeyFile"
  "webUser"
  "daemonUser"
  "group"
];
true
