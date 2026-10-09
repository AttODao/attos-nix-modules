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
      host = "nixos";
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
      privateKeyFile = "/run/secrets/server-private";
    };
  };
  vpn = evaluate [ wireguard ];
  endpointOnly = evaluate [
    {
      modules.public-services."remote.example.test".wireguard-server = {
        enable = true;
        host = "nixos";
        deploy = false;
      };
    }
  ];
  remote = evaluate [
    {
      modules.public-services."remote.example.test".wireguard-server = {
        enable = true;
        host = "remote";
      };
    }
  ];
  disabled = evaluate [
    { modules.public-services."disabled.example.test".wireguard-server.enable = false; }
    {
      modules.incus.virtualMachines.unused.launchConfig = { };
      modules.incus.preseed.storage_pools = [ ];
    }
  ];
  nativePort = evaluate [
    wireguard
    { networking.wireguard.interfaces.wg0.listenPort = 12345; }
  ];
  manifestFor =
    cfg: service:
    builtins.fromJSON (builtins.head cfg.systemd.services.${service}.restartTriggers).text;
  vpnManifest = manifestFor vpn "wireguard-client-config-sync";
  missingKey = builtins.tryEval (
    builtins.deepSeq (manifestFor (evaluate [
      {
        inherit (wireguard) modules;
        networking.wireguard.interfaces.wg0.ips = [ "10.252.0.1/24" ];
      }
    ]) "wireguard-peer-sync") true
  );
  incusModule = {
    modules.incus = {
      enable = true;
      stateDir = "/srv/incus/stamps";
      virtualMachines.guest = {
        metadata = "/srv/images/metadata.tar.xz";
        disk = "/srv/images/disk.qcow2";
        launchConfig = {
          profiles = [ "consumer" ];
          devices.root = {
            type = "disk";
            pool = "consumer-pool";
            path = "/";
          };
        };
      };
      preseed = {
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
  };
  guests = evaluate [ incusModule ];
  nativeIncus = evaluate [ { modules.incus.enable = true; } ];
  nullPreseed = evaluate [
    incusModule
    { modules.incus.preseed = lib.mkForce null; }
  ];
  poolOverride = pools: {
    modules.incus.preseed.storage_pools = lib.mkForce pools;
  };
  invalidPool =
    pools:
    builtins.tryEval (
      builtins.deepSeq
        (evaluate [
          incusModule
          (poolOverride pools)
        ]).systemd.services.incus-preseed.serviceConfig.ExecCondition
        true
    );
  guestManifest = manifestFor guests "incus-virtual-machines";
  bad = modules: lib.any (a: !a.assertion) (evaluate modules).assertions;
  missingDownload = builtins.tryEval (
    builtins.deepSeq
      (evaluate [ { modules.ytdl-sub.enable = true; } ]).virtualisation.oci-containers.containers
      true
  );
  invalidKey =
    path:
    builtins.tryEval (
      # Force generated metadata, not assertions: an unsafe native string must never reach it.
      builtins.deepSeq (manifestFor (evaluate [
        wireguard
        { networking.wireguard.interfaces.wg0.privateKeyFile = lib.mkForce path; }
      ]) "wireguard-peer-sync") true
    );
  c = ytdl.virtualisation.oci-containers.containers.ytdl-sub;
in
assert
  base.home-manager.users == { } && !base.modules.ytdl-sub.enable && !base.modules.incus.enable;
assert base.networking.wireguard.interfaces == { } && !base.virtualisation.incus.enable;
assert
  !(base.systemd.services ? incus-virtual-machines) && !(base.systemd.services ? wireguard-peer-sync);
assert ytdl.home-manager.users == { } && ytdl.modules.docker.enable && !ytdl.modules.swarm.enable;
assert lib.all (a: a.assertion) ytdl.assertions;
assert
  c.image
  == "ghcr.io/jmbannon/ytdl-sub:2026.08.26.post1@sha256:f96bcf1d2896da0177f9c7964407c27830571d1eb96a5886abd605140c69e278"
  && c.pull == "always"
  && !c.autoRemoveOnStop;
assert c.environment.UPDATE_YT_DLP_ON_START == "";
assert c.environment.PUID == "1100" && c.environment.PGID == "1101";
assert lib.elem "/run/secrets/cookies.txt:/config/cookies.txt" c.volumes;
assert lib.hasInfix "install" ytdl.systemd.services.ytdl-sub-config.script;
assert lib.elem "ytdl-sub-config.service" ytdl.systemd.services.docker-ytdl-sub.requires;
assert cookieOverride.virtualisation.oci-containers.containers.ytdl-sub.environment.TZ == "UTC";
assert lib.all (a: a.assertion) vpn.assertions && vpn.home-manager.users == { };
assert vpn.networking.wireguard.interfaces.wg0.privateKeyFile == "/run/secrets/server-private";
assert vpn.networking.wireguard.interfaces.wg0.peers == [ ];
assert vpn.networking.wireguard.interfaces.wg0.listenPort == 51820;
assert vpnManifest.interface == "wg0" && vpnManifest.clientEndpoint == "vpn.example.test:51820";
assert vpnManifest.privateKeyFile == "/run/secrets/server-private";
assert vpnManifest.clientConfigMode == "0600";
assert !missingKey.success;
assert lib.all
  (field: !(builtins.hasAttr field vpn.modules.public-services."vpn.example.test".wireguard-server))
  [
    "interface"
    "privateKeyFile"
    "clientEndpoint"
  ];
assert
  vpnManifest.clients == [
    {
      name = "phone";
      address = "10.252.0.2";
      publicKeyFile = "/run/secrets/phone-public";
      privateKeyFile = "/run/secrets/phone-private";
    }
  ];
assert
  (manifestFor nativePort "wireguard-client-config-sync").clientEndpoint == "vpn.example.test:12345";
assert lib.all (path: !(invalidKey path).success) [
  null
  ../AGENTS.md
  "/nix/store/fake-key"
  builtins.storeDir
  "relative/key"
  "/run/key:unsafe"
  "/run/key\nunsafe"
  "/run/key\runsafe"
];
assert vpn.systemd.services.wireguard-peer-sync.after == [ "wireguard-wg0.service" ];
assert lib.elem "wireguard-wg0.target" vpn.systemd.services.wireguard-peer-sync.wantedBy;
assert vpn.systemd.services.wireguard-client-config-sync.serviceConfig.UMask == "0077";
assert
  vpn.systemd.services.wireguard-client-config-sync.serviceConfig.RuntimeDirectoryMode == "0700";
assert lib.all
  (
    cfg:
    lib.all (a: a.assertion) cfg.assertions
    && cfg.networking.wireguard.interfaces == { }
    && !(cfg.systemd.services ? wireguard-peer-sync)
    && !(cfg.systemd.services ? wireguard-client-config-sync)
  )
  [
    remote
    endpointOnly
    disabled
  ];
assert
  !disabled.virtualisation.incus.enable
  && !(disabled.systemd.services ? incus-preseed)
  && !(disabled.systemd.services ? incus-virtual-machines);
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
assert lib.elem "incus-preseed.service" guests.systemd.services.incus-virtual-machines.requires;
assert
  guests.systemd.services.incus-virtual-machines.unitConfig.RequiresMountsFor
  == [ "/srv/incus/stamps" ];
assert
  nativeIncus.virtualisation.incus.enable && !(nativeIncus.systemd.services ? incus-virtual-machines);
assert guestManifest.virtualMachines.guest.alias == "server-dotfiles-guest";
assert
  !(guests.modules.incus ? initializePool) && !(guests.modules.incus.virtualMachines.guest ? alias);
assert guestManifest.virtualMachines.guest.metadata == "/srv/images/metadata.tar.xz";
assert guestManifest.virtualMachines.guest.disk == "/srv/images/disk.qcow2";
assert
  guestManifest.virtualMachines.guest.launchConfig
  == incusModule.modules.incus.virtualMachines.guest.launchConfig;
assert guestManifest.virtualMachines.guest.managedDeviceNames == [ ];
assert lib.all (a: a.assertion) nullPreseed.assertions;
assert
  !(nativeIncus.systemd.services ? incus-preseed) && !(nullPreseed.systemd.services ? incus-preseed);
assert
  !(lib.elem "incus-preseed.service" nullPreseed.systemd.services.incus-virtual-machines.requires);
assert lib.all
  (
    pools:
    bad [
      incusModule
      (poolOverride pools)
    ]
    && !(invalidPool pools).success
  )
  [
    [ ]
    [
      {
        name = "one";
        driver = "dir";
      }
      {
        name = "two";
        driver = "dir";
      }
    ]
    [ { driver = "dir"; } ]
  ];
assert bad [
  incusModule
  { modules.incus.preseed = lib.mkForce { }; }
];
assert !missingDownload.success;
true
