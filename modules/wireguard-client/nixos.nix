{ config, lib, ... }:
let
  cfg = config.modules.wireguard-client;
  id = name: "WireGuard: ${name}";
  # Interface names may contain characters invalid in shell variable names.
  keyVariable = name: "WIREGUARD_CLIENT_KEY_${builtins.hashString "sha256" name}";
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
      {
        method = "manual";
      }
      // addresses tunnelAddresses
      // lib.optionalAttrs (dns != [ ]) { dns = list dns; };
  profile =
    name: tunnel:
    {
      connection = {
        id = id name;
        type = "wireguard";
        interface-name = name;
        autoconnect = false;
      };
      # Substituted by envsubst in NetworkManager-ensure-profiles. Agent-owned keys fail for
      # user-initiated activation: NetworkManager only asks agents owned by the requesting uid.
      wireguard.private-key = "$" + keyVariable name;
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

    networking.networkmanager.ensureProfiles.profiles = lib.mapAttrs' (
      name: tunnel: lib.nameValuePair "wireguard-${name}" (profile name tunnel)
    ) cfg.tunnels;

    # The service writes profiles with UMask 0177, so keys stay root-only in /run.
    systemd.services.NetworkManager-ensure-profiles.script = lib.mkBefore (
      lib.concatStrings (
        lib.mapAttrsToList (name: tunnel: ''
          ${keyVariable name}="$(< ${lib.escapeShellArg tunnel.privateKeyFile})"
          export ${keyVariable name}
        '') cfg.tunnels
      )
    );
  };
}
