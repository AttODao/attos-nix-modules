# nix-instantiate --eval --strict tests/wireguard-client.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  module = ../modules/wireguard-client;
  cfgFor = modules: t.cfgFor ([ module ] ++ modules);
  base = cfgFor [ ];
  empty = cfgFor [ { modules.wireguard-client.enable = true; } ];
  enabled = cfgFor [
    {
      modules.wireguard-client = {
        enable = true;
        tunnels = {
          wg0 = "/run/secrets/wireguard/wg0.conf";
          wg1 = "/run/secrets/wireguard/wg1.conf";
        };
      };
    }
  ];
  service = enabled.systemd.services.wireguard-client-import;
  python = t.pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  invalidName =
    builtins.tryEval
      (cfgFor [
        {
          modules.wireguard-client = {
            enable = true;
            tunnels."too-long-interface" = "/run/secrets/wg.conf";
          };
        }
      ]).modules.wireguard-client.tunnels;
  invalidPath = builtins.tryEval (
    builtins.deepSeq
      (cfgFor [
        {
          modules.wireguard-client = {
            enable = true;
            tunnels.wg0 = "relative.conf";
          };
        }
      ]).modules.wireguard-client.tunnels
      true
  );
  storePath = builtins.tryEval (
    builtins.deepSeq
      (cfgFor [
        { modules.wireguard-client.tunnels.wg0 = "${t.pkgs.writeText "secret" "not-a-real-key"}"; }
      ]).modules.wireguard-client.tunnels
      true
  );
  pathLiteral = builtins.tryEval (
    builtins.deepSeq
      (cfgFor [
        { modules.wireguard-client.tunnels.wg0 = /run/secrets/wg.conf; }
      ]).modules.wireguard-client.tunnels
      true
  );
  networkManagerConflict =
    builtins.tryEval
      (cfgFor [
        {
          modules.wireguard-client.enable = true;
          networking.networkmanager.enable = false;
        }
      ]).networking.networkmanager.enable;
in
assert !base.modules.wireguard-client.enable;
assert !(base.systemd.services ? wireguard-client-import);
assert empty.networking.networkmanager.enable;
assert !(empty.systemd.services ? wireguard-client-import);
assert enabled.networking.networkmanager.enable;
assert service.description == "Import runtime WireGuard profiles into NetworkManager";
assert service.requires == [ "NetworkManager.service" ];
assert service.after == [ "NetworkManager.service" ];
assert service.partOf == [ "NetworkManager.service" ];
assert service.serviceConfig.Type == "oneshot";
assert service.serviceConfig.RuntimeDirectory == "wireguard-client";
assert service.serviceConfig.RuntimeDirectoryPreserve == "yes";
assert service.serviceConfig.RuntimeDirectoryMode == "0700";
assert service.serviceConfig.UMask == "0077";
assert service.serviceConfig.User == "root" && service.serviceConfig.Group == "root";
assert service.environment.GI_TYPELIB_PATH == "${t.pkgs.networkmanager}/lib/girepository-1.0";
assert service.environment.LC_ALL == "C";
assert lib.hasInfix (builtins.unsafeDiscardStringContext (lib.getExe python)) service.script;
assert lib.hasInfix (builtins.unsafeDiscardStringContext (lib.getExe python)) service.postStop;
assert builtins.elem t.pkgs.networkmanager service.path;
assert
  service.serviceConfig.LoadCredential == [
    "tunnel-0:/run/secrets/wireguard/wg0.conf"
    "tunnel-1:/run/secrets/wireguard/wg1.conf"
  ];
assert lib.hasInfix "import-tunnels.py start /run/wireguard-client" service.script;
assert lib.hasInfix "import-tunnels.py stop /run/wireguard-client" service.postStop;
assert !lib.hasInfix "/run/secrets/wireguard/wg0.conf" service.script;
assert !invalidName.success;
assert !invalidPath.success && !storePath.success && !pathLiteral.success;
assert !networkManagerConflict.success;
true
