{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "opencloud";
  root = ps.require "opencloud" "dataDir" s.cfg.dataDir;
  environmentFile = ps.require "opencloud" "environmentFile" s.cfg.environmentFile;
  configDir = "${root}/config";
  listen =
    if s.standalone then
      {
        address = "127.0.0.1";
        port = "9200";
      }
    else
      ps.backendEndpoint s;
in
{
  options.modules = ps.moduleOptions "opencloud" (
    ps.common "OpenCloud server"
    // {
      dataDir = ps.pathOption "Service root containing the existing config and data directories.";
      environmentFile = ps.pathOption "Runtime OpenCloud environment file, including credentials.";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      services.opencloud = {
        enable = true;
        # The image is the rolling release; production would be a downgrade.
        package = lib.mkDefault pkgs.opencloud;
        address = lib.removeSuffix "]" (lib.removePrefix "[" listen.address);
        port = lib.toInt listen.port;
        url = ps.url s 9200;
        stateDir = "${root}/data";
        inherit environmentFile;
        environment = lib.mapAttrs (_: lib.mkDefault) {
          # Keep the existing opencloud.yaml beside the data instead of /etc/opencloud.
          OC_CONFIG_DIR = configDir;
          # The gateway terminates TLS with a valid certificate; keep verification on.
          OC_INSECURE = "false";
          PROXY_TLS = "false";
          OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD = "false";
        };
      };
      systemd.tmpfiles.settings."10-opencloud-root" = {
        ${root}.d = {
          mode = "0755";
          user = "root";
          group = "root";
        };
        ${configDir}.d = {
          mode = "0700";
          user = "opencloud";
          group = "opencloud";
        };
      };
      systemd.services = {
        opencloud-init-config = {
          unitConfig.RequiresMountsFor = [ root ];
          serviceConfig.ReadWritePaths = [ configDir ];
        };
        opencloud = {
          unitConfig.RequiresMountsFor = [
            root
            environmentFile
          ];
          # A public owner binds the backendUrl address, which must exist first.
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          serviceConfig.ReadWritePaths = [ configDir ];
        };
      };
      networking.firewall = ps.backendFirewall config s [ ];
    })
  ];
}
