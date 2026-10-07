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
    secretService = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[-a-zA-Z0-9@_.:]+[.]service");
      default = null;
      example = "sops-install-secrets.service";
      description = "Existing decryption unit to require and order before importing tunnels. Leave null for activation-script decryption (the sops-nix default).";
    };
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
        using secretService only when the decryption service exists. With sops-nix, order against
        sops-install-secrets.service only if sops.useSystemdActivation is true;
        its default activation-script mode installs secrets before services restart.
        Restart the import unit on rotation.
        An empty mapping creates no import unit.
      '';
    };
  };
}
