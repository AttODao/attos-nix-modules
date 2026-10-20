{
  config,
  lib,
  pkgs,
  ps,
  ...
}:
let
  selected = ps.select config "hermes";
  cfg = selected.cfg;
  dataDir = ps.require "hermes" "dataDir" cfg.dataDir;
  native = config.services.hermes-agent;

  # Default-deny view: whole trees are emptied and only dataDir returns. New host data
  # under these trees stays hidden without changes here.
  sandbox = {
    unitConfig.RequiresMountsFor = [ dataDir ];
    serviceConfig = {
      # Upstream sets ProtectHome = false; tmpfs still allows dataDir under /home.
      ProtectHome = lib.mkForce "tmpfs";
      TemporaryFileSystem = [
        "/mnt:ro"
        "/media:ro"
        "/srv:ro"
        "/opt:ro"
        "/var:ro"
        "/run:ro"
      ];
      BindPaths = [ dataDir ];
      # bash -l rebuilds PATH from the system profile. glibc reaches nscd through
      # /var/run (hidden with /var); static resolvers such as Go read /etc/resolv.conf,
      # which links into /run/systemd/resolve with systemd-resolved.
      BindReadOnlyPaths = [
        "/run/current-system"
        "-/run/nscd:/var/run/nscd"
        "-/run/systemd/resolve"
      ];
      InaccessiblePaths = [ "-/boot" ];
      PrivateDevices = true;
      ProtectProc = "invisible";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictSUIDSGID = true;
      RestrictRealtime = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
      ];
    };
  };

  # Upstream's HERMES_MANAGED locks every config.yaml key. The units pin only the keys Nix
  # writes (the same terminal.cwd default and settings as upstream's merge) through Hermes's
  # managed scope, so Hermes can change the rest with `hermes config set`. Shells outside
  # the units still see the .managed marker and stay locked.
  managedScope.environment = {
    HERMES_MANAGED = lib.mkForce "false";
    HERMES_MANAGED_DIR = "${pkgs.writeTextDir "config.yaml" (
      builtins.toJSON (lib.recursiveUpdate { terminal.cwd = native.workingDirectory; } native.settings)
    )}";
  };
in
{
  config = lib.mkIf selected.enabled {
    services.hermes-agent = {
      enable = true;
      createUser = false;
      inherit (cfg) user group;
      stateDir = dataDir;
      backend = {
        mode = lib.mkDefault "dashboard";
        host = lib.mkDefault (if selected.standalone then "127.0.0.1" else "0.0.0.0");
      };
      # Hermes builds per-task environments itself, as an untrusted Nix user. The
      # terminal's bash -l drops the package wrapper's PATH, so upstream's own
      # runtime tools are repeated here.
      extraPackages = [
        pkgs.nix
        pkgs.devenv
        pkgs.nodejs
        pkgs.ripgrep
        pkgs.ffmpeg-headless
      ];
    };

    systemd.services.hermes-agent = lib.mkMerge [
      sandbox
      managedScope
    ];
    systemd.services.hermes-backend = lib.mkIf (native.backend.mode != "none") (
      lib.mkMerge [
        sandbox
        managedScope
      ]
    );
  };
}
