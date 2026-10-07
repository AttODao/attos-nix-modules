# nix-instantiate --eval --strict tests/swarm.nix --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
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
    t.evalSystem {
      users = [ ];
      inherit modules;
    };
  base = evaluate [ ];
  worker =
    address:
    (evaluate [
      {
        modules.swarm = {
          enable = true;
          role = "worker";
          managerAddress = address;
          joinTokenFile = "/run/secrets/swarm-token";
        };
      }
    ]).config;
  waitCommand = cfg: cfg.systemd.services.docker-network-traefik.serviceConfig.ExecStart;
  joinCommand = cfg: cfg.systemd.services.docker-swarm-join.serviceConfig.ExecStart;
  valid =
    address: host:
    let
      cfg = worker address;
    in
    lib.hasSuffix " wait ${lib.escapeShellArg "http://${host}:2378/traefik-network-ready"}" (
      waitCommand cfg
    )
    && lib.hasSuffix " worker ${lib.escapeShellArg address} %d/join-token" (joinCommand cfg)
    && cfg.modules.docker.enable
    &&
      cfg.systemd.services.docker-swarm-join.serviceConfig.LoadCredential
      == [ "join-token:/run/secrets/swarm-token" ];
  invalid =
    address:
    let
      cfg = worker address;
    in
    !(builtins.tryEval (waitCommand cfg)).success && !(builtins.tryEval (joinCommand cfg)).success;
  manager =
    (evaluate [
      {
        modules.swarm = {
          enable = true;
          role = "manager";
          advertiseAddress = "10.250.0.1";
          networkSubnet = "10.251.0.0/24";
          networkGateway = "10.251.0.1";
          readinessAddress = "10.250.0.1";
        };
      }
    ]).config;
in
assert !base.config.modules.swarm.enable && !base.config.modules.docker.enable;
assert !(base.config.systemd.services ? docker-network-traefik);
assert !(base.options.modules.swarm ? readinessPort);
assert !(base.options.modules.swarm ? networkReadyUrl);
assert valid "10.250.0.1:2377" "10.250.0.1";
assert valid "10.250.0.1" "10.250.0.1";
assert valid "manager" "manager";
assert valid "manager.example.test:2377" "manager.example.test";
assert valid "manager.example.test." "manager.example.test.";
assert valid "[2001:db8::1]:2377" "[2001:db8::1]";
assert valid "[2001:DB8::1]" "[2001:DB8::1]";
assert valid "[::1]:65535" "[::1]";
assert valid "[2001:db8:0:0:0:0:0:1]" "[2001:db8:0:0:0:0:0:1]";
assert lib.all invalid [
  "http://manager:2377"
  "user@manager:2377"
  "manager:2377/path"
  "manager:2377?query"
  "manager:2377#fragment"
  "manager:"
  "manager:0"
  "manager:65536"
  "manager:02377"
  "manager:port"
  "manager:2377:2378"
  "manager name:2377"
  "manager\n"
  "-manager"
  "manager-"
  "manager..test"
  "manager_test"
  "256.250.0.1"
  "010.250.0.1"
  "127.1"
  "2001:db8::1"
  "[manager]:2377"
  "[2001:db8::1"
  "[2001:db8:::1]"
  "[2001::db8::1]"
  "[1:2:3:4:5:6:7:8:9]"
  "[00000::1]"
  "[fe80::1%eth0]"
  "[::1]:"
];
assert lib.hasSuffix (
  " "
  + lib.escapeShellArgs [
    "10.250.0.1"
    "2378"
    "/run/docker-swarm-network-ready/traefik-network-ready"
  ]
) manager.systemd.services.docker-swarm-network-server.serviceConfig.ExecStart;
assert !(manager.systemd.services ? docker-swarm-token-server);
assert
  !lib.hasInfix "worker-token" manager.systemd.services.docker-swarm-network-server.serviceConfig.ExecStart;
assert lib.all (a: a.assertion) manager.assertions;
true
