{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = config.modules.attos-deck;
  pkg = attopkgs.attos-deck;
  toml = pkgs.formats.toml { };
  stateDir = "/var/lib/attos-deck";

  deckSettings = lib.recursiveUpdate (
    {
      state.dir = stateDir;
      style.font = "${pkgs.noto-fonts-cjk-sans-static}/share/fonts/opentype/noto-cjk/NotoSansCJK-Bold.ttc";
      ssh = {
        program = "${pkgs.openssh}/bin/ssh";
        identity = "${stateDir}/id_ed25519";
      };
    }
    // lib.optionalAttrs (config.time.timeZone != null) { timezone = config.time.timeZone; }
  ) cfg.settings;
  deckToml = toml.generate "attos-deck.toml" deckSettings;
  deckConfig = pkgs.runCommand "attos-deck-config-checked.toml" { } ''
    ${pkg}/bin/attos-deck check-config ${deckToml}
    cp ${deckToml} "$out"
  '';

  agentSettings = lib.recursiveUpdate {
    systemctl = "${config.systemd.package}/bin/systemctl";
    restart_failed = true;
    deny = [
      "sshd.service"
      "attos-deck-agent.socket"
    ];
  } cfg.agent.settings;
  agentToml = toml.generate "attos-deck-agent.toml" agentSettings;
  agentConfig = pkgs.runCommand "attos-deck-agent-config-checked.toml" { } ''
    ${pkg}/bin/attos-deck-agent check-config ${agentToml}
    cp ${agentToml} "$out"
  '';

  # The deck owns its SSH identity: generated once in the state directory and
  # logged so the consumer can authorize it for remote agents.
  keygen = pkgs.writeShellScript "attos-deck-keygen" ''
    set -eu
    key="$STATE_DIRECTORY/id_ed25519"
    if [ ! -e "$key" ]; then
      ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C "attos-deck@${config.networking.hostName}" -f "$key"
    fi
    echo "attos-deck SSH public key: $(cat "$key.pub")"
  '';

  hardening = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    SystemCallArchitectures = "native";
    UMask = "0077";
  };
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      users.groups.attos-deck = { };
      # Stream Deck MK.2 only; the service reaches it through the group, not uaccess (no seat on servers).
      services.udev.extraRules = ''
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0080", GROUP="attos-deck", MODE="0660"
      '';
      environment.systemPackages = [ pkg ];
      systemd.services.attos-deck = {
        description = "attos-deck Stream Deck controller";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        environment.RUST_LOG = lib.mkDefault "info";
        serviceConfig = hardening // {
          ExecStartPre = keygen;
          ExecStart = "${pkg}/bin/attos-deck daemon --config ${deckConfig}";
          DynamicUser = true;
          SupplementaryGroups = [
            "attos-deck"
          ]
          ++ lib.optional (cfg.agent.enable && cfg.agent.socketGroup != null) cfg.agent.socketGroup;
          StateDirectory = "attos-deck";
          StateDirectoryMode = "0700";
          LoadCredential = lib.mapAttrsToList (name: path: "${name}:${path}") cfg.credentials;
          Restart = "always";
          RestartSec = 2;
          CapabilityBoundingSet = "";
          DevicePolicy = "closed";
          DeviceAllow = [ "char-hidraw rw" ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
          MemoryDenyWriteExecute = true;
        };
      };
    })
    (lib.mkIf (cfg.agent.enable && cfg.agent.socketGroup != null) {
      # `attos-deck-agent ssh` is the forced command of the consumer's SSH account.
      environment.systemPackages = [ pkg ];
      systemd.sockets.attos-deck-agent = {
        description = "attos-deck agent socket";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "/run/attos-deck-agent.sock";
          SocketUser = "root";
          SocketGroup = cfg.agent.socketGroup;
          SocketMode = "0660";
          Accept = true;
          MaxConnections = 4;
        };
      };
      systemd.services."attos-deck-agent@" = {
        description = "attos-deck agent request";
        serviceConfig = hardening // {
          ExecStart = "${pkg}/bin/attos-deck-agent serve --config ${agentConfig}";
          StandardInput = "socket";
          StandardOutput = "socket";
          StandardError = "journal";
          RuntimeMaxSec = 60;
          RestrictAddressFamilies = [ "AF_UNIX" ];
        };
      };
    })
  ];
}
