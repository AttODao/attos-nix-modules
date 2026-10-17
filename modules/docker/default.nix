{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  imports = [ ./nixos.nix ];
  options.modules.docker = {
    enable = lib.mkEnableOption "shared Docker and OCI service support";
    networks = mkOption {
      internal = true;
      type = types.attrsOf (
        types.submodule {
          options = {
            subnet = mkOption {
              type = types.nullOr types.nonEmptyStr;
              default = null;
              description = "Fixed subnet in CIDR form; null lets Docker choose and skips the IPAM check.";
            };
            gateway = mkOption {
              type = types.nullOr types.nonEmptyStr;
              default = null;
              description = "Fixed gateway address; requires subnet.";
            };
            options = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "Bridge driver options that the existing network must also carry.";
            };
          };
        }
      );
      default = { };
      description = ''
        Local Docker bridge networks owned by shared service modules. Each gets a
        docker-network-<name> unit that creates the bridge when missing and verifies an
        existing one (local bridge, options, and IPAM when subnet is set) without ever
        recreating it. Containers attached by name re-run the check before starting.
      '';
    };
  };
}
