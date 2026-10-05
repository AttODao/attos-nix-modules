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
  downloads = {
    modules.ytdl-sub = {
      enable = true;
      dataDir = "/srv/downloads";
      cookieFile = "/run/secrets/cookies.txt";
      subscriptionFiles = {
        youtube = "/srv/subscriptions/youtube.yaml";
        twitch = "/srv/subscriptions/twitch.yaml";
      };
      uid = 1100;
      gid = 1101;
    };
  };
  ytdl = evaluate [ downloads ];
  cookieOverride = evaluate [
    downloads
    { virtualisation.oci-containers.containers.ytdl-sub.environment.TZ = "UTC"; }
  ];
  wireguard = {
    modules.public-services."vpn.example.test".wireguard-server = {
      enable = true;
      privateKeyFile = "/run/secrets/server-private";
      serverPublicKeyFile = "/run/secrets/server-public";
      clientDns = "10.252.0.1";
      clients.phone = {
        address = "10.252.0.2";
        publicKeyFile = "/run/secrets/phone-public";
        privateKeyFile = "/run/secrets/phone-private";
      };
    };
    networking.wireguard.interfaces.wg0 = {
      ips = [ "10.252.0.1/24" ];
      listenPort = 51820;
    };
  };
  vpn = evaluate [ wireguard ];
  remote = evaluate [
    {
      modules.public-services."remote.example.test".wireguard-server = {
        enable = true;
        deploy = false;
      };
    }
  ];
  incusModule = {
    modules.incus = {
      enable = true;
      initializePool = "consumer-pool";
      stateDir = "/srv/incus/stamps";
      containers.guest = {
        alias = "consumer-image";
        metadata = "/srv/images/metadata.tar.xz";
        rootfs = "/srv/images/rootfs.squashfs";
        launchConfig = {
          profiles = [ "consumer" ];
          devices.root = {
            type = "disk";
            pool = "consumer-pool";
            path = "/";
          };
        };
      };
    };
    virtualisation.incus.preseed = {
      storage_pools = [
        {
          name = "consumer-pool";
          driver = "dir";
          config.source = "/srv/incus/pool";
        }
      ];
      profiles = [
        {
          name = "consumer";
          config = { };
          devices = { };
        }
      ];
    };
  };
  guests = evaluate [ incusModule ];
  nativeIncus = evaluate [ { modules.incus.enable = true; } ];
  bad = modules: lib.any (a: !a.assertion) (evaluate modules).assertions;
  missingDownload = builtins.tryEval (
    builtins.deepSeq
      (evaluate [ { modules.ytdl-sub.enable = true; } ]).virtualisation.oci-containers.containers
      true
  );
  invalidKey =
    builtins.tryEval
      (evaluate [
        { modules.public-services."bad.example.test".wireguard-server.privateKeyFile = ../AGENTS.md; }
      ]).modules.public-services."bad.example.test".wireguard-server.privateKeyFile;
  c = ytdl.virtualisation.oci-containers.containers.ytdl-sub;
in
assert
  base.home-manager.users == { } && !base.modules.ytdl-sub.enable && !base.modules.incus.enable;
assert base.networking.wireguard.interfaces == { } && !base.virtualisation.incus.enable;
assert
  !(base.systemd.services ? incus-containers) && !(base.systemd.services ? wireguard-peer-sync);
assert ytdl.home-manager.users == { } && ytdl.modules.docker.enable && !ytdl.modules.swarm.enable;
assert lib.all (a: a.assertion) ytdl.assertions;
assert c.image == "ghcr.io/jmbannon/ytdl-sub:latest" && c.pull == "always" && !c.autoRemoveOnStop;
assert c.environment.PUID == "1100" && c.environment.PGID == "1101";
assert lib.elem "/run/secrets/cookies.txt:/config/cookies.txt" c.volumes;
assert lib.hasInfix "install" ytdl.systemd.services.ytdl-sub-config.script;
assert lib.elem "ytdl-sub-config.service" ytdl.systemd.services.docker-ytdl-sub.requires;
assert cookieOverride.virtualisation.oci-containers.containers.ytdl-sub.environment.TZ == "UTC";
assert lib.all (a: a.assertion) vpn.assertions && vpn.home-manager.users == { };
assert vpn.networking.wireguard.interfaces.wg0.privateKeyFile == "/run/secrets/server-private";
assert vpn.networking.wireguard.interfaces.wg0.peers == [ ];
assert vpn.systemd.services.wireguard-peer-sync.after == [ "wireguard-wg0.service" ];
assert lib.elem "wireguard-wg0.target" vpn.systemd.services.wireguard-peer-sync.wantedBy;
assert vpn.systemd.services.wireguard-client-config-sync.serviceConfig.UMask == "0077";
assert
  vpn.systemd.services.wireguard-client-config-sync.serviceConfig.RuntimeDirectoryMode == "0700";
assert
  remote.networking.wireguard.interfaces == { } && !(remote.systemd.services ? wireguard-peer-sync);
assert bad [
  wireguard
  {
    networking.wireguard.interfaces.wg0.peers = [
      {
        publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        allowedIPs = [ "10.252.0.3/32" ];
      }
    ];
  }
];
assert bad [
  wireguard
  {
    modules.public-services."vpn.example.test".wireguard-server.clients.other = {
      address = "10.252.0.2";
      publicKeyFile = "/run/other-public";
      privateKeyFile = "/run/other-private";
    };
  }
];
assert bad [
  wireguard
  { networking.wireguard.useNetworkd = true; }
];
assert lib.all (a: a.assertion) guests.assertions && guests.virtualisation.incus.enable;
assert !guests.modules.docker.enable && !guests.modules.swarm.enable;
assert !(guests.modules.public-services ? "vpn.example.test");
assert guests.networking.nftables.enable;
assert guests.systemd.services.incus-preseed.restartIfChanged == false;
assert lib.hasInfix "condition consumer-pool" (
  builtins.head guests.systemd.services.incus-preseed.serviceConfig.ExecCondition
);
assert lib.elem "incus-preseed.service" guests.systemd.services.incus-containers.requires;
assert
  guests.systemd.services.incus-containers.unitConfig.RequiresMountsFor == [ "/srv/incus/stamps" ];
assert
  nativeIncus.virtualisation.incus.enable && !(nativeIncus.systemd.services ? incus-containers);
assert bad [
  incusModule
  { modules.incus.initializePool = lib.mkForce "wrong-pool"; }
];
assert !missingDownload.success && !invalidKey.success;
true
