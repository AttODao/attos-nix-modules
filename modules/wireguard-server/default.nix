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
  octet = "(0|[1-9][0-9]?|1[0-9][0-9]|2[0-4][0-9]|25[0-5])";
  ipv4 = types.addCheck types.str (
    value: builtins.match "${octet}\\.${octet}\\.${octet}\\.${octet}" value != null
  );
  interfaceType = types.addCheck types.str (
    value: builtins.match "[a-zA-Z0-9][a-zA-Z0-9_-]{0,14}" value != null
  );
in
{
  options.modules.public-services = ps.option "wireguard-server" (
    ps.common "WireGuard server and runtime client configuration" null
    // {
      interface = mkOption {
        type = interfaceType;
        default = "wg0";
        description = "Native networking.wireguard interface to manage; addresses, listenPort and other network policy remain consumer-owned.";
      };
      privateKeyFile = ps.pathOption "Runtime server private key file; key provisioning, permissions and rotation belong to the consumer.";
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
      clientEndpoint = mkOption {
        type = types.nullOr types.singleLineStr;
        default = null;
        description = "Client endpoint override (host:port or [IPv6]:port); defaults to this hostname and the native interface listenPort.";
      };
      clientConfigsDirectory = mkOption {
        type = ps.absolutePath;
        default = "/run/wireguard/client-configs";
        description = "Sensitive generated client configurations (0600). Execution identity and directory access are configured with ordinary systemd overrides.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = selected.assertions; }
    (lib.mkIf selected.enabled (
      let
        cfg = selected.cfg;
        require = ps.require "wireguard-server";
        privateKeyFile = require "privateKeyFile" cfg.privateKeyFile;
        serverPublicKeyFile = require "serverPublicKeyFile" cfg.serverPublicKeyFile;
        clientDns = require "clientDns" cfg.clientDns;
        native = config.networking.wireguard.interfaces.${cfg.interface};
        clients = lib.mapAttrsToList (name: client: {
          inherit name;
          inherit (client) address;
          publicKeyFile = require "clients.${name}.publicKeyFile" client.publicKeyFile;
          privateKeyFile = require "clients.${name}.privateKeyFile" client.privateKeyFile;
        }) cfg.clients;
        clientEndpoint =
          if cfg.clientEndpoint != null then
            cfg.clientEndpoint
          else
            "${selected.hostname}:${toString (require "networking.wireguard.interfaces.${cfg.interface}.listenPort (or clientEndpoint)" native.listenPort)}";
        metadata = pkgs.writeText "wireguard-runtime.json" (
          builtins.toJSON {
            inherit
              privateKeyFile
              serverPublicKeyFile
              clients
              clientDns
              clientEndpoint
              ;
            inherit (cfg) interface clientConfigsDirectory;
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
            assertion =
              native.privateKey == null
              && native.privateKeyFile == privateKeyFile
              && !native.generatePrivateKeyFile;
            message = "wireguard-server: supply the server key only through privateKeyFile; key generation/provisioning belongs to the consumer.";
          }
          {
            assertion =
              cfg.clientEndpoint != null
              || (native.listenPort != null && native.listenPort > 0 && native.listenPort <= 65535);
            message = "wireguard-server: a valid native listenPort or explicit clientEndpoint is required.";
          }
        ];

        networking.wireguard = {
          useNetworkd = lib.mkDefault false;
          interfaces.${cfg.interface}.privateKeyFile = lib.mkDefault privateKeyFile;
        };
        environment.systemPackages = [ qr ];

        systemd.services.wireguard-peer-sync = {
          description = "Synchronize runtime WireGuard peers";
          after = [ "wireguard-${cfg.interface}.service" ];
          requires = [ "wireguard-${cfg.interface}.service" ];
          wantedBy = [ "wireguard-${cfg.interface}.target" ];
          partOf = [ "wireguard-${cfg.interface}.service" ];
          restartTriggers = [ metadata ];
          serviceConfig = {
            ExecStart = "${peerSync}/bin/wireguard-peer-sync";
            Type = "oneshot";
            RemainAfterExit = true;
            User = lib.mkDefault "root";
            Group = lib.mkDefault "root";
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
            User = lib.mkDefault "root";
            Group = lib.mkDefault "root";
            UMask = lib.mkDefault "0077";
            RuntimeDirectory = lib.mkDefault (
              lib.optional runtimeConfigs (lib.removePrefix "/run/" cfg.clientConfigsDirectory)
            );
            RuntimeDirectoryMode = lib.mkDefault "0700";
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
