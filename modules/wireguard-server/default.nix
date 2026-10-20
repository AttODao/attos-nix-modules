{
  config,
  lib,
  pkgs,
  attopkgs,
  ps,
  ...
}:
let
  selected = ps.select config "wireguard-server";
  inherit (lib) mkOption types;
  mode = types.strMatching "0[0-7]{3}";
  octet = "(0|[1-9][0-9]?|1[0-9][0-9]|2[0-4][0-9]|25[0-5])";
  ipv4 = types.addCheck types.str (
    value: builtins.match "${octet}\\.${octet}\\.${octet}\\.${octet}" value != null
  );
  publicKey = types.strMatching "[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=";
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
              ipv6Address = mkOption {
                type = types.nullOr (types.strMatching "[0-9a-f:]+");
                default = null;
                example = "fd00::2";
                description = "Optional unique client IPv6 address in canonical lowercase form without a CIDR suffix; emitted as /128 and adds ::/0 to the client AllowedIPs. The consumer configures the server wg0 IPv6 address, forwarding and NAT66 or routing.";
              };
              publicKey = mkOption {
                type = publicKey;
                description = "Base64 client public key, declared as a native wg0 peer. Public keys are not secret and are stored in the Nix store.";
              };
              presharedKeyFile = ps.pathOption "Optional runtime preshared key file, used by the native peer and the generated client configuration.";
              privateKeyFile = ps.pathOption "Runtime client private key file for client configuration generation.";
            };
          }
        );
        default = { };
        description = "Clients indexed by safe lowercase names, declared as native wg0 peers named after the client. Private and preshared key files are read only at runtime, never during evaluation.";
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
        serverPublicKeyFile = require "serverPublicKeyFile" cfg.serverPublicKeyFile;
        clientDns = require "clientDns" cfg.clientDns;
        interface = "wg0";
        native = config.networking.wireguard.interfaces.${interface};
        clients = lib.mapAttrsToList (name: client: {
          inherit name;
          inherit (client) address ipv6Address presharedKeyFile;
          privateKeyFile = require "clients.${name}.privateKeyFile" client.privateKeyFile;
        }) cfg.clients;
        clientEndpoint = "${selected.hostname}:${toString (require "networking.wireguard.interfaces.wg0.listenPort" native.listenPort)}";
        metadata = pkgs.writeText "wireguard-runtime.json" (
          builtins.toJSON {
            inherit
              serverPublicKeyFile
              clients
              clientDns
              clientEndpoint
              ;
            inherit (cfg) clientConfigsDirectory;
            clientConfigMode = cfg.clientConfigSync.fileMode;
          }
        );
        runtime = lib.getExe attopkgs.wireguard-runtime;
        qr =
          pkgs.runCommand "wg-qr"
            {
              nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
              meta.mainProgram = "wg-qr";
            }
            ''
              makeBinaryWrapper ${runtime} $out/bin/wg-qr \
                --add-flag qr --add-flag ${metadata} \
                --prefix PATH : ${lib.makeBinPath [ pkgs.qrencode ]}
            '';
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
              let
                addresses = lib.concatMap (
                  client: [ client.address ] ++ lib.optional (client.ipv6Address != null) client.ipv6Address
                ) clients;
              in
              builtins.length addresses == builtins.length (lib.unique addresses);
            message = "wireguard-server: client addresses must be unique.";
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

        networking.wireguard.interfaces.${interface} = {
          listenPort = lib.mkDefault 51820;
          peers = lib.mapAttrsToList (name: client: {
            inherit name;
            inherit (client) publicKey presharedKeyFile;
            allowedIPs = [
              "${client.address}/32"
            ]
            ++ lib.optional (client.ipv6Address != null) "${client.ipv6Address}/128";
          }) cfg.clients;
        };
        boot.kernel.sysctl = lib.mkIf cfg.ipv4Forwarding {
          "net.ipv4.conf.all.forwarding" = 1;
          "net.ipv4.conf.default.forwarding" = 1;
        };
        environment.systemPackages = [ qr ];

        systemd.services.wireguard-client-config-sync = {
          description = "Generate runtime WireGuard client configurations";
          wantedBy = [ "multi-user.target" ];
          restartTriggers = [ metadata ];
          serviceConfig = {
            ExecStart = "${runtime} configs ${metadata}";
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
