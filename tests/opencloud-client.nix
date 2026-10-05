# nix-instantiate --eval --strict tests/opencloud-client.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) pkgs lib;
  base = t.cfgFor [ ];
  enabledCfg = t.cfgFor [ { modules.opencloud-client.enable = true; } ];
  enabled = t.hm enabledCfg "test";
  service = enabled.systemd.user.services.opencloud;
  hiddenEntry = "[Desktop Entry]\nType=Application\nName=OpenCloud Desktop\nHidden=true\n";
in
assert !base.modules.opencloud-client.enable;
assert !(base.environment.etc ? "OpenCloud/OpenCloud.conf");
assert builtins.elem pkgs.opencloud-desktop enabled.home.packages;
assert enabled.xdg.configFile."autostart/OpenCloud.desktop".text == hiddenEntry;
assert enabled.xdg.configFile."autostart/OpenCloud.desktop.backup".text == hiddenEntry;
assert enabled.xdg.configFile."autostart/OpenCloud.desktop.backup".force;
assert enabled.xdg.dataFile."applications/opencloudcmd.desktop".text == hiddenEntry;
assert service.Service.ExecStart == [ "${pkgs.opencloud-desktop}/bin/opencloud" ];
assert service.Service.Restart == "on-failure";
assert service.Unit.After == [ "graphical-session.target" ];
assert service.Install.WantedBy == [ "graphical-session.target" ];
assert
  enabledCfg.environment.etc."OpenCloud/OpenCloud.conf".text
  == "[Wizard]\nServerUrl=https://cloud.attodao.cc\n";
assert lib.hasSuffix ".drv" enabled.home.activationPackage.drvPath;
true
