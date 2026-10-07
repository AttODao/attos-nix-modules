# Typed infrastructure inputs, independent of any consumer checkout or host identity.
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib pkgs;
  evaluate =
    modules:
    t.evalSystem {
      users = [ ];
      inherit modules;
    };
  base = evaluate [ ];
  cfg = modules: (evaluate modules).config;
  good = c: lib.all (a: a.assertion) c.assertions;
  manifest =
    c: unit: builtins.fromJSON (builtins.head c.systemd.services.${unit}.restartTriggers).text;
  dns = cfg [
    {
      modules.dns = {
        enable = true;
        listenAddresses = [
          "127.0.0.1"
          "192.0.2.1"
          "10.252.0.1"
        ];
      };
    }
  ];
  defaultDns = cfg [ { modules.dns.enable = true; } ];
  ollama = cfg [
    {
      modules.public-services."backend.example.test".ollama = {
        enable = true;
        host = "nixos";
        package = pkgs.ollama-vulkan;
        home = "/srv/ollama";
        modelsDir = "/srv/model-store";
        listenAddress = "192.0.2.1";
        port = 11435;
        loadModels = [
          "embeddinggemma"
          "qwen3-vl:4b-instruct"
        ];
        environmentVariables = {
          OLLAMA_VULKAN = "1";
          OLLAMA_CONTEXT_LENGTH = "16384";
        };
      };
    }
  ];
  ollamaHome = cfg [
    {
      modules.public-services."backend.example.test".ollama = {
        enable = true;
        host = "nixos";
        home = "/srv/other-ollama";
      };
    }
  ];
  vpnInput = {
    users.users.operator = {
      isNormalUser = true;
      group = "users";
    };
    modules.public-services."vpn.example.test".wireguard-server = {
      enable = true;
      host = "nixos";
      serverPublicKeyFile = "/run/secrets/server-public";
      clientDns = "10.252.0.1";
      peerSync = {
        user = "operator";
        group = "users";
        ambientCapabilities = [ "CAP_NET_ADMIN" ];
      };
      clientConfigSync = {
        user = "operator";
        group = "users";
        umask = "0007";
        runtimeDirectoryMode = "0770";
        fileMode = "0660";
      };
      ipv4Forwarding = true;
    };
    networking.wireguard.interfaces.wg0 = {
      ips = [ "10.252.0.1/24" ];
      privateKeyFile = "/run/secrets/server-private";
    };
  };
  vpn = cfg [ vpnInput ];
  remoteVpn = cfg [
    {
      modules.public-services."vpn.example.test".wireguard-server = {
        enable = true;
        host = "remote";
        ipv4Forwarding = true;
        peerSync.user = "unavailable";
        clientConfigSync.fileMode = "0660";
      };
    }
  ];
  preseed = {
    storage_pools = [
      {
        name = "existing";
        driver = "lvm";
        config = {
          source = "/dev/consumer-disk";
          "lvm.vg_name" = "existing_vg";
        };
      }
    ];
    networks = [
      {
        name = "consumerbr0";
        type = "bridge";
        config."ipv4.address" = "10.88.0.1/24";
      }
    ];
    profiles = [
      {
        name = "consumer";
        devices.root = {
          type = "disk";
          path = "/";
          pool = "existing";
          size = "460GiB";
        };
      }
    ];
  };
  incusInput = {
    modules.incus = {
      enable = true;
      inherit preseed;
      stateDir = "/var/lib/existing-incus-stamps";
      initrdKernelModules = [ "dm_thin_pool" ];
      preseedKernelModules = [ "dm_thin_pool" ];
      provisionKernelModules = [
        "dm_snapshot"
        "dm_thin_pool"
      ];
      containers.guest = {
        metadata = "/srv/images/metadata.tar.xz";
        rootfs = "/srv/images/rootfs.squashfs";
        launchConfig = {
          profiles = [ "consumer" ];
          devices.uinput = {
            type = "unix-char";
            path = "/dev/uinput";
            gid = "174";
            mode = "0660";
          };
        };
        managedDeviceNames = [ "uinput" ];
      };
    };
  };
  incus = cfg [ incusInput ];
  noPreseed = cfg [
    incusInput
    { modules.incus.preseed = lib.mkForce null; }
  ];
  ranges = [
    { start = 80; }
    { start = 443; }
    {
      start = 19132;
      end = 19137;
      protocol = "udp";
    }
    {
      start = 25500;
      end = 25600;
    }
  ]
  ++ map (start: { inherit start; }) [
    25
    143
    465
    587
    993
    4190
  ];
  gatewayInput = {
    modules = {
      swarm = {
        role = "manager";
        advertiseAddress = "192.0.2.1";
        networkSubnet = "10.251.0.0/24";
        networkGateway = "10.251.0.1";
      };
      traefik = {
        enable = true;
        dataDir = "/srv/traefik";
        environmentFile = "/run/secrets/cloudflare";
        publishedPortRanges = ranges;
      };
      public-services = {
        "game.example.test".mineos = {
          enable = true;
          host = "remote";
        };
        "mail.example.test".mailserver = {
          enable = true;
          host = "remote";
          backendAddress = "192.0.2.2";
        };
      };
    };
  };
  gateway = cfg [ gatewayInput ];
  defaultGateway = cfg [
    gatewayInput
    { modules.traefik.publishedPortRanges = lib.mkForce null; }
  ];
  badRange =
    value:
    !good (cfg [
      gatewayInput
      { modules.traefik.publishedPortRanges = lib.mkForce value; }
    ]);
  disabled = cfg [
    {
      modules = {
        dns.listenAddresses = [ "192.0.2.1" ];
        public-services."backend.example.test".ollama = {
          host = "nixos";
          home = "/srv/unused";
          listenAddress = "192.0.2.1";
        };
        incus = {
          inherit preseed;
          initrdKernelModules = [ "dm_thin_pool" ];
          preseedKernelModules = [ "dm_thin_pool" ];
        };
      };
    }
  ];
  opts = base.options.modules;
  ollamaOpts = (opts.public-services.type.nestedTypes.elemType.getSubOptions [ ]).ollama;
  rangeOpts =
    opts.traefik.publishedPortRanges.type.nestedTypes.elemType.nestedTypes.elemType.getSubOptions
      [ ];
in
assert !base.config.modules.dns.enable && !base.config.services.dnsmasq.enable;
assert !(opts ? ollama) && !base.config.services.ollama.enable;
assert !base.config.modules.incus.enable && !base.config.virtualisation.incus.enable;
assert !(disabled.systemd.services ? dnsmasq) && !(disabled.systemd.services ? ollama);
assert
  disabled.virtualisation.incus.preseed == null && !(disabled.systemd.services ? incus-preseed);
assert disabled.services.ollama.home == base.config.services.ollama.home;
assert defaultDns.services.dnsmasq.settings.listen-address == [ "127.0.0.1" ];
assert
  dns.services.dnsmasq.settings.listen-address == [
    "127.0.0.1"
    "192.0.2.1"
    "10.252.0.1"
  ];
assert !opts.dns.listenAddresses.type.nestedTypes.elemType.check "";
assert good ollama && ollama.services.ollama.package == pkgs.ollama-vulkan;
assert
  ollama.services.ollama.home == "/srv/ollama"
  && ollama.services.ollama.modelsDir == "/srv/model-store";
assert ollama.services.ollama.host == "192.0.2.1" && ollama.services.ollama.port == 11435;
assert
  ollama.services.ollama.loadModels == [
    "embeddinggemma"
    "qwen3-vl:4b-instruct"
  ];
assert ollama.services.ollama.environmentVariables.OLLAMA_VULKAN == "1";
assert ollama.services.ollama.environmentVariables.OLLAMA_CONTEXT_LENGTH == "16384";
assert ollama.services.ollama.environmentVariables.OLLAMA_NO_CLOUD == "1";
assert
  ollama.systemd.services.ollama.unitConfig.RequiresMountsFor == [
    "/srv/ollama"
    "/srv/model-store"
  ];
assert
  !ollama.services.ollama.syncModels
  && ollamaHome.services.ollama.modelsDir == "/srv/other-ollama/models";
assert
  !ollamaOpts.port.type.check 65536
  && !ollamaOpts.environmentVariables.type.nestedTypes.elemType.check 1;
assert good vpn && vpn.systemd.services.wireguard-peer-sync.serviceConfig.User == "operator";
assert vpn.systemd.services.wireguard-peer-sync.serviceConfig.Group == "users";
assert
  vpn.systemd.services.wireguard-peer-sync.serviceConfig.AmbientCapabilities == [ "CAP_NET_ADMIN" ];
assert vpn.systemd.services.wireguard-client-config-sync.serviceConfig.User == "operator";
assert vpn.systemd.services.wireguard-client-config-sync.serviceConfig.Group == "users";
assert vpn.systemd.services.wireguard-client-config-sync.serviceConfig.UMask == "0007";
assert
  vpn.systemd.services.wireguard-client-config-sync.serviceConfig.RuntimeDirectoryMode == "0770";
assert (manifest vpn "wireguard-client-config-sync").clientConfigMode == "0660";
assert
  vpn.boot.kernel.sysctl."net.ipv4.conf.all.forwarding" == 1
  && vpn.boot.kernel.sysctl."net.ipv4.conf.default.forwarding" == 1;
assert good remoteVpn && !(remoteVpn.systemd.services ? wireguard-peer-sync);
assert !(remoteVpn.boot.kernel.sysctl ? "net.ipv4.conf.all.forwarding");
assert good incus && incus.virtualisation.incus.preseed == preseed;
assert lib.elem "dm_thin_pool" incus.boot.initrd.kernelModules;
assert
  incus.systemd.services.incus-preseed.serviceConfig.ExecStartPre
  == [ "${pkgs.kmod}/bin/modprobe dm_thin_pool" ];
assert
  incus.systemd.services.incus-containers.serviceConfig.ExecStartPre == [
    "${pkgs.kmod}/bin/modprobe dm_snapshot"
    "${pkgs.kmod}/bin/modprobe dm_thin_pool"
  ];
assert lib.hasInfix "condition existing" (
  builtins.head incus.systemd.services.incus-preseed.serviceConfig.ExecCondition
);
assert
  incus.systemd.services.incus-containers.unitConfig.RequiresMountsFor
  == [ "/var/lib/existing-incus-stamps" ];
assert
  (manifest incus "incus-containers").containers.guest.launchConfig
  == incusInput.modules.incus.containers.guest.launchConfig;
assert (manifest incus "incus-containers").containers.guest.managedDeviceNames == [ "uinput" ];
assert
  !(noPreseed.systemd.services ? incus-preseed)
  && !(lib.elem "incus-preseed.service" noPreseed.systemd.services.incus-containers.requires);
assert good gateway;
assert
  gateway.virtualisation.oci-containers.containers.traefik.ports == [
    "80:80"
    "443:443"
    "19132-19137:19132-19137/udp"
    "25500-25600:25500-25600"
    "25:25"
    "143:143"
    "465:465"
    "587:587"
    "993:993"
    "4190:4190"
  ];
assert lib.elem "25500:25500" defaultGateway.virtualisation.oci-containers.containers.traefik.ports;
assert badRange (ranges ++ [ { start = 8080; } ]);
assert badRange (ranges ++ [ { start = 80; } ]);
assert badRange (builtins.tail ranges);
assert badRange [
  {
    start = 100;
    end = 90;
  }
];
assert !rangeOpts.start.type.check 0;
assert !rangeOpts.protocol.type.check "sctp";
true
