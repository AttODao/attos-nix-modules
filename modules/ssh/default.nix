{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
in
{
  imports = [
    ./nixos.nix
    ../openssh
  ];

  options.modules.ssh.enable = lib.mkEnableOption "shared SSH client configuration";

  # Keep the existing SSH client enable distinct from the standalone server.
  options.modules.ssh.server.enable = lib.mkEnableOption "localhost-only SSH server";

  config = lib.mkMerge [
    (lib.mkIf config.modules.ssh.enable {
      home-manager.sharedModules = [ ./home.nix ];
    })
    (lib.mkIf config.modules.ssh.server.enable {
      assertions = [
        {
          assertion = !(lib.any (entry: ps.isLocal config entry.cfg) (ps.entries config "ssh"));
          message = "SSH: standalone server and public local deployment cannot be enabled together.";
        }
      ];
      modules.openssh = {
        enable = true;
        listenAddresses = lib.mkDefault [ { addr = "127.0.0.1"; } ];
        openFirewall = lib.mkDefault false;
      };
    })
  ];
}
