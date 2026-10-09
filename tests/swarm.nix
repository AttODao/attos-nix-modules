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
  waitCommand = cfg: cfg.systemd.services.docker-swarm-networks.serviceConfig.ExecStart;
  joinCommand = cfg: cfg.systemd.services.docker-swarm-join.serviceConfig.ExecStart;
  valid =
    address: host:
    let
      cfg = worker address;
    in
    lib.hasSuffix " wait ${lib.escapeShellArg "http://${host}:2378/networks-ready"}" (waitCommand cfg)
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
  fetching =
    (evaluate [
      {
        modules.swarm = {
          enable = true;
          role = "worker";
          managerAddress = "10.250.0.1:2377";
          joinTokenFile = "/run/docker-swarm/worker-token";
          readinessPort = 12378;
          tokenFetch = {
            enable = true;
            url = "http://10.250.0.1:12378/worker-token";
            sourceAddress = "10.250.0.2";
          };
        };
      }
    ]).config;
  transporting =
    (evaluate [
      {
        modules.swarm = {
          enable = true;
          role = "manager";
          advertiseAddress = "10.250.0.1";
          readinessAddress = "10.250.0.1";
          tokenTransport = {
            enable = true;
            allowedAddresses = [ "10.250.0.2" ];
          };
        };
      }
    ]).config;
  badTransport =
    (evaluate [
      {
        modules.swarm = {
          enable = true;
          role = "manager";
          tokenTransport.enable = true;
        };
      }
    ]).config;
  manager =
    (evaluate [
      {
        modules.swarm = {
          enable = true;
          role = "manager";
          advertiseAddress = "10.250.0.1";
          readinessAddress = "10.250.0.1";
        };
      }
    ]).config;
in
assert !base.config.modules.swarm.enable && !base.config.modules.docker.enable;
assert !(base.config.systemd.services ? docker-swarm-networks);
assert base.config.modules.swarm.readinessPort == 2378;
assert !base.config.modules.swarm.tokenTransport.enable;
assert !base.config.modules.swarm.tokenFetch.enable;
assert !(base.config.systemd.services ? docker-swarm-token-fetch);
assert !(base.options.modules.swarm ? networkReadyUrl);
assert
  !(base.options.modules.swarm ? networkSubnet) && !(base.options.modules.swarm ? networkGateway);
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
    "/run/docker-swarm-network-ready/networks-ready"
  ]
) manager.systemd.services.docker-swarm-network-server.serviceConfig.ExecStart;
assert !(manager.systemd.services ? docker-swarm-token-server);
assert
  !lib.hasInfix "worker-token" manager.systemd.services.docker-swarm-network-server.serviceConfig.ExecStart;
assert lib.all (a: a.assertion) manager.assertions;
assert lib.all (a: a.assertion) fetching.assertions;
assert lib.all (a: a.assertion) transporting.assertions;
assert lib.any (a: !a.assertion) badTransport.assertions;
assert lib.hasInfix "http://10.250.0.1:12378/networks-ready" (waitCommand fetching);
assert lib.hasSuffix (
  " fetch "
  + lib.escapeShellArgs [
    "http://10.250.0.1:12378/worker-token"
    "10.250.0.2"
    "/run/docker-swarm/worker-token"
  ]
) fetching.systemd.services.docker-swarm-token-fetch.serviceConfig.ExecStart;
assert lib.elem "docker-swarm-token-fetch.service"
  fetching.systemd.services.docker-swarm-join.requires;
assert lib.elem "docker-swarm-token-fetch.service"
  fetching.systemd.services.docker-swarm-join.after;
assert
  fetching.systemd.services.docker-swarm-join.serviceConfig.LoadCredential
  == [ "join-token:/run/docker-swarm/worker-token" ];
assert
  transporting.systemd.services.docker-swarm-network-server.serviceConfig.LoadCredential
  == [ "worker-token:/run/docker-swarm/worker-token" ];
assert transporting.systemd.services.docker-swarm-network-server.serviceConfig.DynamicUser;
assert lib.elem "docker-swarm-init.service"
  transporting.systemd.services.docker-swarm-network-server.requires;
assert lib.hasInfix "%d/worker-token"
  transporting.systemd.services.docker-swarm-network-server.serviceConfig.ExecStart;
assert lib.hasSuffix "10.250.0.2"
  transporting.systemd.services.docker-swarm-network-server.serviceConfig.ExecStart;
assert !(manager.systemd.services.docker-swarm-network-server.serviceConfig ? LoadCredential);
true
