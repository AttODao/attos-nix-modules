{ config, lib, ... }:
let
  cfg = config.modules.wireguard-client;
  id = name: "WireGuard: ${name}";
  isIPv6 = lib.hasInfix ":";
  list = values: lib.concatMapStrings (value: "${value};") values;
  addresses =
    values: lib.listToAttrs (lib.imap1 (index: lib.nameValuePair "address${toString index}") values);
  ipSection =
    family: tunnel:
    let
      select = if family == "ipv6" then isIPv6 else value: !isIPv6 value;
      tunnelAddresses = lib.filter select tunnel.addresses;
      dns = lib.filter select tunnel.dns;
    in
    if tunnelAddresses == [ ] then
      { method = "disabled"; }
    else
      { method = "manual"; } // addresses tunnelAddresses // lib.optionalAttrs (dns != [ ]) { dns = list dns; };
  profile = name: tunnel: {
    connection = {
      id = id name;
      type = "wireguard";
      interface-name = name;
      autoconnect = false;
    };
    # 1 = agent-owned: NetworkManager requests the key from nm-file-secret-agent.
    wireguard.private-key-flags = 1;
    ipv4 = ipSection "ipv4" tunnel;
    ipv6 = ipSection "ipv6" tunnel;
  }
  // lib.listToAttrs (
    map (
      peer:
      lib.nameValuePair "wireguard-peer.${peer.publicKey}" (
        {
          allowed-ips = list peer.allowedIPs;
        }
        // lib.optionalAttrs (peer.endpoint != null) { inherit (peer) endpoint; }
        // lib.optionalAttrs (peer.persistentKeepalive != null) {
          persistent-keepalive = peer.persistentKeepalive;
        }
      )
    ) tunnel.peers
  );
in
{
  config = lib.mkIf cfg.enable {
    # A normal assignment deliberately exposes an explicitly false consumer value.
    networking.networkmanager.enable = true;

    networking.networkmanager.ensureProfiles = {
      profiles = lib.mapAttrs' (name: tunnel: lib.nameValuePair "wireguard-${name}" (profile name tunnel)) cfg.tunnels;
      secrets.entries = lib.mapAttrsToList (name: tunnel: {
        matchId = id name;
        matchType = "wireguard";
        matchSetting = "wireguard";
        key = "private-key";
        file = tunnel.privateKeyFile;
      }) cfg.tunnels;
    };
  };
}
