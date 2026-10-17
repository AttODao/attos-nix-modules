{ lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  inherit (lib) mkOption types;
  interfaceName = types.addCheck types.str (
    name: builtins.match "[a-zA-Z0-9_=+.-]{1,15}" name != null && name != "." && name != ".."
  );
  publicKey = types.strMatching "[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=";
  peerType = types.submodule {
    options = {
      publicKey = mkOption {
        type = publicKey;
        description = "Base64 public key of the server peer. Public keys are not secret and are stored in the Nix store.";
      };
      endpoint = mkOption {
        type = types.nullOr types.singleLineStr;
        default = null;
        example = "vpn.example.org:51820";
        description = "Peer endpoint as host:port; null leaves it unset.";
      };
      allowedIPs = mkOption {
        type = types.listOf types.singleLineStr;
        example = [ "0.0.0.0/0" ];
        description = "Addresses with CIDR masks routed to this peer.";
      };
      persistentKeepalive = mkOption {
        type = types.nullOr (types.ints.between 1 65535);
        default = null;
        description = "Keepalive interval in seconds; null disables it.";
      };
    };
  };
  tunnelType = types.submodule {
    options = {
      privateKeyFile = mkOption {
        type = ps.absolutePath;
        description = "Quoted absolute runtime path of the decrypted client private key, read by NetworkManager-ensure-profiles.service. Nix path literals and store paths are rejected.";
      };
      addresses = mkOption {
        type = types.nonEmptyListOf types.singleLineStr;
        example = [ "10.0.0.2/32" ];
        description = "Interface addresses with CIDR masks (IPv4 or IPv6).";
      };
      dns = mkOption {
        type = types.listOf types.singleLineStr;
        default = [ ];
        description = "DNS server addresses (IPv4 or IPv6) used while the tunnel is active.";
      };
      peers = mkOption {
        type = types.nonEmptyListOf peerType;
        description = "WireGuard peers of this tunnel.";
      };
    };
  };
in
{
  imports = [ ./nixos.nix ];

  options.modules.wireguard-client = {
    enable = lib.mkEnableOption "declarative NetworkManager WireGuard client profiles";
    tunnels = mkOption {
      type = types.addCheck (types.attrsOf tunnelType) (
        tunnels: lib.all interfaceName.check (builtins.attrNames tunnels)
      );
      default = { };
      description = ''
        Tunnels keyed by interface name (1–15 letters, numbers, _, =, +, ., -; not . or ..).
        Each becomes a runtime NetworkManager profile "WireGuard: <interface>" with autoconnect
        disabled. Private keys are read from their runtime files when
        NetworkManager-ensure-profiles.service runs and written into the root-only profile under
        /run/NetworkManager/system-connections, never into the Nix store. Decryption,
        permissions and rotation belong to the consumer; restart that service after rotation.
        Further profile keys can be added through the standard
        networking.networkmanager.ensureProfiles.profiles."wireguard-<interface>".
      '';
    };
  };
}
