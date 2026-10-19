{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
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
      # Hermes builds per-task environments itself, as an untrusted Nix user.
      extraPackages = [
        pkgs.nix
        pkgs.devenv
      ];
    };

    systemd.services.hermes-agent = sandbox;
    systemd.services.hermes-backend = lib.mkIf (native.backend.mode != "none") sandbox;
  };
}
