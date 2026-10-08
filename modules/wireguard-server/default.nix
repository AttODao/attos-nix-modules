{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "wireguard-server";
  inherit (lib) mkOption types;
  mode = types.strMatching "0[0-7]{3}";
  octet = "(0|[1-9][0-9]?|1[0-9][0-9]|2[0-4][0-9]|25[0-5])";
  ipv4 = types.addCheck types.str (
    value: builtins.match "${octet}\\.${octet}\\.${octet}\\.${octet}" value != null
  );
in
{
  options.modules = ps.moduleOptions "wireguard-server" (
    ps.common "WireGuard server and runtime client configuration"
    // {
      serverPublicKeyFile = ps.pathOption "Runtime server public key file used to generate client configurations.";
      clients = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              address = mkOption {
                type = ipv4;
                description = "Unique client IPv4 address without a CIDR suffix; emitted as /32.";
              };
              publicKeyFile = ps.pathOption "Runtime client public key file.";
              privateKeyFile = ps.pathOption "Runtime client private key file for client configuration generation.";
            };
          }
        );
        default = { };
        description = "Clients indexed by safe lowercase names. Keys are read only by runtime scripts, never during evaluation.";
      };
      clientDns = mkOption {
        type = types.nullOr types.singleLineStr;
        default = null;
        description = "Required client DNS server IP address (IPv4 or IPv6). The consumer supplies a reachable resolver.";
      };
      clientConfigsDirectory = mkOption {
        type = ps.absolutePath;
        default = "/run/wireguard/client-configs";
        description = "Sensitive generated client configurations. Configure execution identity, file mode and runtime directory access with clientConfigSync.";
      };
      peerSync = {
        user = mkOption {
          type = types.nonEmptyStr;
          default = "root";
          description = "Existing user running peer synchronization; must be able to read the server private key and client public keys.";
        };
        group = mkOption {
          type = types.nonEmptyStr;
          default = "root";
          description = "Existing group running peer synchronization; does not create a group.";
        };
        ambientCapabilities = mkOption {
          type = types.listOf (
            types.enum [
              "CAP_NET_ADMIN"
              "CAP_SYS_ADMIN"
            ]
          );
          default = [ ];
          description = "Ambient network administration capabilities for non-root peer synchronization. CAP_NET_ADMIN manages peers; entering a network namespace also requires CAP_SYS_ADMIN.";
        };
      };
      clientConfigSync = {
        user = mkOption {
          type = types.nonEmptyStr;
          default = "root";
          description = "Existing user generating and owning client configurations; must be able to read the server public key and client private keys.";
        };
        group = mkOption {
          type = types.nonEmptyStr;
          default = "root";
          description = "Existing group for client configuration generation and its runtime directory; does not create a group.";
        };
        umask = mkOption {
          type = mode;
          default = "0077";
          description = "Four-digit octal process umask for client configuration generation. Final configuration permissions use fileMode.";
        };
        fileMode = mkOption {
          type = types.enum [
            "0600"
            "0640"
            "0660"
          ];
          default = "0600";
          description = "Permissions applied before atomically publishing client configurations. Group access exposes private keys; only use a trusted operational group.";
        };
        runtimeDirectoryMode = mkOption {
          type = mode;
          default = "0700";
          description = "Four-digit octal mode for the systemd-managed client configuration directory under /run. Other directories remain consumer-provisioned.";
        };
      };
      ipv4Forwarding = mkOption {
        type = types.bool;
        default = false;
        description = "Enable net.ipv4.conf.all.forwarding and net.ipv4.conf.default.forwarding on the owner OS. Does not configure addresses, firewall, NAT or IPv6 forwarding.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = selected.assertions; }
    (lib.mkIf selected.enabled (
      let
        cfg = selected.cfg;
        require = ps.require "wireguard-server";
        # Native WG accepts any string; reject unsafe/non-runtime paths before manifest generation.
        privateKeyFile =
          if ps.absolutePath.check native.privateKeyFile then
            native.privateKeyFile
          else
            throw "wireguard-server: networking.wireguard.interfaces.wg0.privateKeyFile must be a quoted runtime absolute path string, outside the Nix store and without colon or CR/LF.";
        serverPublicKeyFile = require "serverPublicKeyFile" cfg.serverPublicKeyFile;
        clientDns = require "clientDns" cfg.clientDns;
        interface = "wg0";
        native = config.networking.wireguard.interfaces.${interface};
        clients = lib.mapAttrsToList (name: client: {
          inherit name;
          inherit (client) address;
          publicKeyFile = require "clients.${name}.publicKeyFile" client.publicKeyFile;
          privateKeyFile = require "clients.${name}.privateKeyFile" client.privateKeyFile;
        }) cfg.clients;
        clientEndpoint = "${selected.hostname}:${toString (require "networking.wireguard.interfaces.wg0.listenPort" native.listenPort)}";
        metadata = pkgs.writeText "wireguard-runtime.json" (
          builtins.toJSON {
            inherit
              privateKeyFile
              serverPublicKeyFile
              clients
              clientDns
              clientEndpoint
              ;
            inherit interface;
            inherit (cfg) clientConfigsDirectory;
            clientConfigMode = cfg.clientConfigSync.fileMode;
            listenPort = native.listenPort;
            namespace =
              if native.interfaceNamespace != null then native.interfaceNamespace else native.socketNamespace;
          }
        );
        application =
          name: command: inputs:
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [
              pkgs.python3
              pkgs.wireguard-tools
            ]
            ++ inputs;
            text = ''
              exec python3 ${./wireguard-runtime.py} ${command} ${metadata} "$@"
            '';
          };
        peerSync = application "wireguard-peer-sync" "peers" [ pkgs.iproute2 ];
        clientSync = application "wireguard-client-config-sync" "configs" [ ];
        qr = application "wg-qr" "qr" [ pkgs.qrencode ];
        runtimeConfigs = lib.hasPrefix "/run/" cfg.clientConfigsDirectory;
      in
      {
        assertions = [
          {
            assertion = lib.all (client: builtins.match "[a-z0-9][a-z0-9_-]*" client.name != null) clients;
            message = "wireguard-server: client names must contain only lowercase letters, numbers, underscores and hyphens, starting with a letter or number.";
          }
          {
            assertion =
              builtins.length clients == builtins.length (lib.unique (map (client: client.address) clients));
            message = "wireguard-server: client addresses must be unique.";
          }
          {
            assertion = native.peers == [ ];
            message = "wireguard-server: runtime peer synchronization owns this interface's peers; do not also declare native peers.";
          }
          {
            assertion = !config.networking.wireguard.useNetworkd && native.type == "wireguard";
            message = "wireguard-server: runtime synchronization requires the native script-based WireGuard backend (useNetworkd = false, type = wireguard).";
          }
          {
            assertion = native.privateKey == null && !native.generatePrivateKeyFile;
            message = "wireguard-server: supply the server key only through privateKeyFile; key generation/provisioning belongs to the consumer.";
          }
          {
            assertion = native.listenPort != null && native.listenPort > 0 && native.listenPort <= 65535;
            message = "wireguard-server: a valid native wg0 listenPort is required.";
          }
        ];

        networking.wireguard = {
          useNetworkd = lib.mkDefault false;
          interfaces.${interface}.listenPort = lib.mkDefault 51820;
        };
        boot.kernel.sysctl = lib.mkIf cfg.ipv4Forwarding {
          "net.ipv4.conf.all.forwarding" = 1;
          "net.ipv4.conf.default.forwarding" = 1;
        };
        environment.systemPackages = [ qr ];

        systemd.services.wireguard-peer-sync = {
          description = "Synchronize runtime WireGuard peers";
          after = [ "wireguard-${interface}.service" ];
          requires = [ "wireguard-${interface}.service" ];
          wantedBy = [ "wireguard-${interface}.target" ];
          partOf = [ "wireguard-${interface}.service" ];
          restartTriggers = [ metadata ];
          serviceConfig = {
            ExecStart = "${peerSync}/bin/wireguard-peer-sync";
            Type = "oneshot";
            RemainAfterExit = true;
            User = lib.mkDefault cfg.peerSync.user;
            Group = lib.mkDefault cfg.peerSync.group;
            AmbientCapabilities = lib.mkDefault cfg.peerSync.ambientCapabilities;
            UMask = lib.mkDefault "0077";
            RuntimeDirectory = lib.mkDefault "wireguard-peer-sync";
            RuntimeDirectoryMode = lib.mkDefault "0700";
            CapabilityBoundingSet = lib.mkDefault [
              "CAP_NET_ADMIN"
              "CAP_SYS_ADMIN"
            ];
            NoNewPrivileges = lib.mkDefault true;
          };
        };
        systemd.services.wireguard-client-config-sync = {
          description = "Generate runtime WireGuard client configurations";
          wantedBy = [ "multi-user.target" ];
          restartTriggers = [ metadata ];
          serviceConfig = {
            ExecStart = "${clientSync}/bin/wireguard-client-config-sync";
            Type = "oneshot";
            RemainAfterExit = true;
            User = lib.mkDefault cfg.clientConfigSync.user;
            Group = lib.mkDefault cfg.clientConfigSync.group;
            UMask = lib.mkDefault cfg.clientConfigSync.umask;
            RuntimeDirectory = lib.mkDefault (
              lib.optional runtimeConfigs (lib.removePrefix "/run/" cfg.clientConfigsDirectory)
            );
            RuntimeDirectoryMode = lib.mkDefault cfg.clientConfigSync.runtimeDirectoryMode;
            RuntimeDirectoryPreserve = lib.mkDefault "restart";
            ReadWritePaths = lib.mkDefault [ cfg.clientConfigsDirectory ];
            NoNewPrivileges = lib.mkDefault true;
            PrivateTmp = lib.mkDefault true;
            ProtectHome = lib.mkDefault true;
            ProtectSystem = lib.mkDefault "strict";
          };
        };
      }
    ))
  ];
}
