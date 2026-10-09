{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  cfg = t.cfgFor;
  valid = c: lib.all (a: a.assertion) c.assertions;
  network = {
    subnet = "172.30.99.0/29";
    gateway = "172.30.99.1";
    address = "172.30.99.2";
  };
  gatewayInput = {
    modules.traefik = {
      enable = true;
      dataDir = "/srv/gateway";
      environmentFile = "/run/secrets/gateway.env";
      nativeBackendNetwork = network;
    };
    modules.swarm = {
      role = "manager";
      advertiseAddress = "192.0.2.1";
    };
  };
  gateway = cfg [ gatewayInput ];
  gatewayWithBackend = cfg [
    gatewayInput
    {
      modules.public-services."forge.example.test".forgejo = {
        enable = true;
        host = "remote";
      };
    }
  ];
  bridgeOff = cfg [ { modules.traefik.nativeBackendNetwork = network; } ];
  ssh =
    socket:
    cfg [
      {
        modules.openssh = {
          enable = true;
          startWhenNeeded = socket;
          listenServices = [ "wireguard-vpn.service" ];
        };
      }
    ];
  vmInput = {
    modules.incus = {
      enable = true;
      stateDir = "/srv/incus-stamps";
      virtualMachines.worker = {
        metadata = "/srv/images/meta.tar.xz";
        disk = "/srv/images/vm.qcow2";
        launchConfig = { };
        credentialFiles = {
          "/var/lib/worker/token.env" = "/run/secrets/worker.env";
          "/var/lib/worker/other.env" = "/run/secrets/other user.env";
        };
        credentialRestartUnits = [ "worker.service" ];
      };
    };
  };
  vm = cfg [ vmInput ];
  vmLatest = cfg [
    vmInput
    { modules.incus.package = t.pkgs.incus; }
  ];
  vmOff = cfg [
    vmInput
    {
      modules.incus.enable = lib.mkForce false;
      modules.incus.package = t.pkgs.incus;
    }
  ];
  vmEmpty = cfg [
    vmInput
    {
      modules.incus.virtualMachines.worker = {
        credentialFiles = lib.mkForce { };
        credentialRestartUnits = lib.mkForce [ ];
      };
    }
  ];
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
  mcsInput = {
    enable = true;
    dataDir = "/srv/mcsm";
    webUser = "mcsm-web";
    daemonUser = "mcsm-daemon";
    group = "mcsm";
    generateDaemonKey = true;
  };
  mcs = cfg [
    accounts
    { modules.mcsmanager = mcsInput; }
  ];
  remote = cfg [
    {
      modules.public-services."mine.example.test".mcsmanager = {
        enable = true;
        host = "remote";
        generateDaemonKey = true;
      };
    }
  ];
  external = cfg [
    {
      modules.public-services."mine.example.test".mcsmanager = {
        enable = true;
        host = "nixos";
        deploy = false;
        generateDaemonKey = true;
      };
    }
  ];
  badKey = cfg [
    accounts
    {
      modules.mcsmanager = mcsInput // {
        daemonKeyFile = "/run/secrets/external-key";
      };
    }
  ];
  badDestination =
    builtins.tryEval
      (cfg [
        {
          modules.incus.virtualMachines.worker = {
            metadata = "/srv/meta.tar.xz";
            disk = "/srv/disk.qcow2";
            launchConfig = { };
            credentialFiles."/" = "/run/secrets/key";
          };
        }
      ]).modules.incus.virtualMachines.worker.credentialFiles;
  badSource =
    builtins.tryEval
      (cfg [
        {
          modules.incus.virtualMachines.worker = {
            metadata = "/srv/meta.tar.xz";
            disk = "/srv/disk.qcow2";
            launchConfig = { };
            credentialFiles."/var/lib/worker/key" = "/nix/store/secret";
          };
        }
      ]).modules.incus.virtualMachines.worker.credentialFiles."/var/lib/worker/key";
  badNetwork = cfg [
    gatewayInput
    {
      modules.traefik.nativeBackendNetwork.address = lib.mkForce network.gateway;
    }
  ];
  forbiddenDestinations =
    map
      (
        destination:
        builtins.tryEval
          (cfg [
            {
              modules.incus.virtualMachines.worker = {
                metadata = "/srv/meta.tar.xz";
                disk = "/srv/disk.qcow2";
                launchConfig = { };
                credentialFiles.${destination} = "/run/secrets/key";
              };
            }
          ]).modules.incus.virtualMachines.worker.credentialFiles
      )
      [
        "/etc/token.env"
        "/root/token.env"
        "/root//token.env"
        "/foo"
        "/var/lib/../token.env"
      ];
  endpoint =
    backendUrl:
    cfg [
      {
        modules.public-services."external.example.org".vaultwarden = {
          enable = true;
          host = "external";
          deploy = false;
          inherit backendUrl;
        };
      }
    ];
  ps = import ../modules/public-services/lib.nix { inherit lib; };
  delivery = vm.systemd.services.incus-vm-credentials-worker;
  key = mcs.systemd.services.mcsmanager-key;
in
assert valid gateway && valid vm && valid vmLatest && valid mcs;
assert lib.all (result: !result.success) forbiddenDestinations;
assert !valid (endpoint null);
assert valid (endpoint "https://external-backend.example.org");
assert ps.backendNetworks (endpoint "https://external-backend.example.org") == [ ];
assert
  (builtins.head (ps.routes (endpoint "https://external-backend.example.org"))).cfg.backendUrl
  == "https://external-backend.example.org";
assert vm.modules.incus.package.drvPath == t.pkgs.incus-lts.drvPath;
assert vm.virtualisation.incus.package.drvPath == t.pkgs.incus-lts.drvPath;
assert vmLatest.virtualisation.incus.package.drvPath == t.pkgs.incus.drvPath;
assert vmLatest.virtualisation.incus.clientPackage.drvPath == t.pkgs.incus.client.drvPath;
assert vmOff.virtualisation.incus.package.drvPath == t.pkgs.incus-lts.drvPath;
assert !(bridgeOff.systemd.services ? docker-network-traefik-native);
assert lib.elem "name=traefik-native,ip=172.30.99.2,gw-priority=1"
  gateway.virtualisation.oci-containers.containers.traefik.networks;
assert
  gatewayWithBackend.virtualisation.oci-containers.containers.traefik.networks == [
    "name=traefik-native,ip=172.30.99.2,gw-priority=1"
    "backend-forgejo"
  ];
assert lib.elem "docker-network-traefik-native.service"
  gateway.systemd.services.docker-traefik.requires;
assert gateway.systemd.services.docker-traefik.environment.DOCKER_HOST == "unix:///run/docker.sock";
assert lib.hasInfix "network inspect" gateway.systemd.services.docker-traefik.preStart;
assert lib.elem "wireguard-vpn.service" (ssh false).systemd.services.sshd.wants;
assert lib.elem "wireguard-vpn.service" (ssh true).systemd.sockets.sshd.after;
assert !(vmOff.systemd.services ? incus-vm-credentials-worker);
assert !(vmEmpty.systemd.services ? incus-vm-credentials-worker);
assert delivery.requires == [ "incus-virtual-machines.service" ];
assert delivery.serviceConfig.UMask == "0077" && delivery.serviceConfig.Restart == "on-failure";
assert lib.hasInfix "--force-local --project default" delivery.script;
assert lib.hasInfix "/run/secrets/worker.env" delivery.script;
assert lib.hasInfix (lib.escapeShellArg "/run/secrets/other user.env") delivery.script;
assert lib.hasInfix "--mode 0600" delivery.script;
assert lib.hasInfix "mkdir -p -m 0700" delivery.script;
assert !lib.hasInfix "install -d" delivery.script;
assert lib.hasInfix "mv -fT --" delivery.script;
assert lib.hasInfix "systemctl restart worker.service" delivery.script;
assert key.unitConfig.ConditionPathExists == "!/srv/mcsm/daemon-key";
assert key.serviceConfig.UMask == "0077";
assert lib.elem "mcsmanager-key.service" mcs.systemd.services.mcsmanager-daemon.requires;
assert lib.elem "daemon-key:/srv/mcsm/daemon-key"
  mcs.systemd.services.mcsmanager-web.serviceConfig.LoadCredential;
assert !(remote.systemd.services ? mcsmanager-key) && !(external.systemd.services ? mcsmanager-key);
assert !valid badKey && !valid badNetwork && !badDestination.success && !badSource.success;
true
