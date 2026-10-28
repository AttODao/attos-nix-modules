{
  config,
  lib,
  pkgs,
  attopkgs,
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
      ]
      ++ map (path: "-${path}") cfg.readOnlyPaths;
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

  # OS全体を境界にするときは、agentのtoolがgatewayの子としてsudo・system全体への
  # 書込みを使えるようupstreamのhardeningも外す。/tmpはSSH sessionと共有する。
  unsandboxed.serviceConfig = {
    NoNewPrivileges = lib.mkForce false;
    ProtectSystem = lib.mkForce false;
    PrivateTmp = lib.mkForce false;
  };

  # upstreamの全key固定ではなく、Nixが書くkeyだけを同じmanaged scopeで固定する。
  # sandbox無効時はPAM sessionにも渡し、login shell・Desktop SSHとstateを共有する。
  managedDir = pkgs.writeTextDir "config.yaml" (
    builtins.toJSON (lib.recursiveUpdate { terminal.cwd = native.workingDirectory; } native.settings)
  );
  # Bot ScreenのlauncherはgatewayのPATHとSSHのlogin shellの両方でこれらを使う。
  botDesktopPackages = with pkgs; [
    tigervnc
    xfwm4
    xfce4-panel
    xfdesktop
    xfce4-settings
    xfce4-terminal
    dbus
    xauth
    xdpyinfo
    setxkbmap
    xprop
    xsetroot
    xset
    at-spi2-core
    attopkgs.cua-driver
  ];
  managedScope.environment = {
    HERMES_MANAGED = lib.mkForce "false";
    HERMES_MANAGED_DIR = "${managedDir}";
  }
  // lib.optionalAttrs cfg.botDesktop {
    # 明示指定でPMによる~/.cua-driverへの独自copyのinstall・repairを避ける。
    HERMES_CUA_DRIVER_CMD = lib.getExe attopkgs.cua-driver;
  };
in
{
  config = lib.mkIf selected.enabled (
    lib.mkMerge [
      {
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

        systemd.services.hermes-agent = lib.mkMerge (
          [ managedScope ] ++ lib.optional cfg.sandbox sandbox ++ lib.optional (!cfg.sandbox) unsandboxed
        );
        systemd.services.hermes-backend = lib.mkIf (native.backend.mode != "none") (
          lib.mkMerge (
            [ managedScope ] ++ lib.optional cfg.sandbox sandbox ++ lib.optional (!cfg.sandbox) unsandboxed
          )
        );
      }
      (lib.mkIf cfg.botDesktop {
        assertions = [
          {
            assertion = !cfg.sandbox;
            message = "hermes: botDesktop requires sandbox = false; the default-deny sandbox hides /tmp/.X11-unix and other desktop resources.";
          }
        ];
        services.hermes-agent.extraPackages = botDesktopPackages;
        environment.systemPackages = botDesktopPackages;
        # Desktop SSHのhermes serveにもNix管理のdriverを使わせる。
        environment.sessionVariables.HERMES_CUA_DRIVER_CMD = lib.getExe attopkgs.cua-driver;
        fonts.packages = [ pkgs.dejavu_fonts ];
      })
      (lib.mkIf (!cfg.sandbox) {
        services.hermes-agent.addToSystemPackages = true;
        environment.sessionVariables = {
          HERMES_HOME = "${dataDir}/.hermes";
          HERMES_MANAGED = "false";
          HERMES_MANAGED_DIR = "${managedDir}";
        };
        # Hermes DesktopのSSH接続はremoteでpython3を実行する。
        environment.systemPackages = [ pkgs.python3 ];
      })
    ]
  );
}
