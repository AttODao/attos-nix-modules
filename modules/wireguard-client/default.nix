{ lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  tunnelsType = lib.types.addCheck (lib.types.attrsOf ps.absolutePath) (
    tunnels:
    lib.all (
      name: builtins.match "[a-zA-Z0-9_=+.-]{1,15}" name != null && name != "." && name != ".."
    ) (builtins.attrNames tunnels)
  );
in
{
  imports = [ ./nixos.nix ];

  options.modules.wireguard-client = {
    enable = lib.mkEnableOption "temporary NetworkManager WireGuard client profiles";
    tunnels = lib.mkOption {
      type = tunnelsType;
      default = { };
      description = ''
        Interface names (1–15 letters, numbers, _, =, +, ., -; not . or ..)
        mapped to quoted absolute runtime paths of decrypted WireGuard configs.
        Nix path literals and store paths are rejected. Profiles are named
        "WireGuard: <interface>" and imported temporarily with autoconnect disabled.
        Secret discovery, decryption, permissions and rotation belong to the consumer.
        Files are read with systemd LoadCredential at service start; order decryption
        using standard systemd.services.wireguard-client-import.requires and after
        (for example sops-install-secrets.service), and restart this unit on rotation.
        An empty mapping creates no import unit.
      '';
    };
  };
}
