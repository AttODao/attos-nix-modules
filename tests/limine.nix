# nix-instantiate --eval --strict tests/limine.nix \
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
  enabled = t.cfgFor [ { modules.limine.enable = true; } ];
  overridden = t.cfgFor [
    { modules.limine.enable = true; }
    {
      boot = {
        kernelPackages = pkgs.linuxPackages_latest;
        kernelParams = lib.mkForce [
          "debug"
          "loglevel=7"
        ];
        consoleLogLevel = 7;
        initrd.verbose = true;
        plymouth.enable = false;
        loader = {
          limine.maxGenerations = 3;
          efi.canTouchEfiVariables = false;
        };
      };
    }
  ];
  defaultParams = [
    "quiet"
    "udev.log_level=3"
    "rd.systemd.show_status=auto"
  ];
  unsafeParams = [
    "mitigations=off"
    "nowatchdog"
    "nmi_watchdog=0"
  ];
in
assert !base.modules.limine.enable;
assert !base.boot.loader.limine.enable;
assert !base.boot.loader.systemd-boot.enable;
assert lib.all (param: !(lib.elem param base.boot.kernelParams)) defaultParams;
assert enabled.modules.limine.enable;
assert enabled.boot.loader.limine.enable;
assert !enabled.boot.loader.systemd-boot.enable;
assert enabled.boot.loader.efi.canTouchEfiVariables;
assert enabled.boot.loader.limine.maxGenerations == 10;
assert enabled.boot.kernelPackages.kernel.version == pkgs.linuxPackages.kernel.version;
assert enabled.boot.plymouth.enable;
assert enabled.boot.consoleLogLevel == 3;
assert !enabled.boot.initrd.verbose;
assert lib.all (param: lib.elem param enabled.boot.kernelParams) defaultParams;
assert lib.all (param: !(lib.elem param enabled.boot.kernelParams)) unsafeParams;
assert overridden.boot.kernelPackages.kernel.version == pkgs.linuxPackages_latest.kernel.version;
assert lib.elem "debug" overridden.boot.kernelParams;
assert lib.elem "loglevel=7" overridden.boot.kernelParams;
assert lib.all (param: !(lib.elem param overridden.boot.kernelParams)) defaultParams;
assert overridden.boot.consoleLogLevel == 7;
assert overridden.boot.initrd.verbose;
assert !overridden.boot.plymouth.enable;
assert overridden.boot.loader.limine.maxGenerations == 3;
assert !overridden.boot.loader.efi.canTouchEfiVariables;
true
