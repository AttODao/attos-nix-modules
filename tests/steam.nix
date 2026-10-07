# nix-instantiate --eval --strict tests/steam.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix {
    inherit nixpkgs homeManager system;
    nixpkgsConfig.allowUnfree = true;
  };

  baseCfg = t.cfgFor [ ];
  base = t.hm baseCfg "test";

  enabledCfg = t.cfgFor [ { modules.steam.enable = true; } ];
  enabled = t.hm enabledCfg "test";

  firewallCfg = t.cfgFor [
    { modules.steam.enable = true; }
    {
      programs.steam = {
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
      };
    }
  ];

  publicFirewall = t.cfgFor [
    {
      modules.steam = {
        enable = true;
        firewall = {
          remotePlay = true;
          dedicatedServer = true;
          localNetworkGameTransfers = true;
        };
      };
    }
  ];
  disabledFirewall = t.cfgFor [ { modules.steam.firewall.remotePlay = true; } ];

  multiCfg = t.evalSystem {
    users = [
      "alice"
      "bob"
    ];
    modules = [ { modules.steam.enable = true; } ];
  };
  alice = t.hm multiCfg.config "alice";
  bob = t.hm multiCfg.config "bob";
in
assert !baseCfg.modules.steam.enable;
assert !baseCfg.modules.pcmanfm.enable;
assert !baseCfg.programs.steam.enable;
assert !(base.xdg.mimeApps.defaultApplications ? "x-scheme-handler/steam");
assert enabledCfg.modules.steam.enable;
assert enabledCfg.modules.pcmanfm.enable;
assert enabledCfg.programs.steam.enable;
assert !enabledCfg.programs.steam.remotePlay.openFirewall;
assert !enabledCfg.programs.steam.dedicatedServer.openFirewall;
assert !enabledCfg.programs.steam.localNetworkGameTransfers.openFirewall;
assert enabled.xdg.mimeApps.enable;
assert enabled.xdg.mimeApps.defaultApplications."x-scheme-handler/steam" == [ "steam.desktop" ];
assert enabled.xdg.mimeApps.defaultApplications."x-scheme-handler/steamlink" == [ "steam.desktop" ];
assert !disabledFirewall.programs.steam.remotePlay.openFirewall;
assert publicFirewall.programs.steam.remotePlay.openFirewall;
assert publicFirewall.programs.steam.dedicatedServer.openFirewall;
assert publicFirewall.programs.steam.localNetworkGameTransfers.openFirewall;
assert firewallCfg.programs.steam.remotePlay.openFirewall;
assert firewallCfg.programs.steam.dedicatedServer.openFirewall;
assert firewallCfg.programs.steam.localNetworkGameTransfers.openFirewall;
assert alice.xdg.mimeApps.defaultApplications."x-scheme-handler/steam" == [ "steam.desktop" ];
assert bob.xdg.mimeApps.defaultApplications."x-scheme-handler/steamlink" == [ "steam.desktop" ];
true
