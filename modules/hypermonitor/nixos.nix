{
  config,
  lib,
  pkgs,
  ps,
  attopkgs,
  ...
}:
let
  s = ps.select config "hypermonitor";
  cfg = s.cfg;
  pkg = if cfg.package != null then cfg.package else attopkgs.hypermonitor;
  toml = pkgs.formats.toml { };
  stateDir = "/var/lib/${cfg.stateDirectory}";
  credentialDir = "/run/credentials/hypermonitor.service";
  agent = config.modules.attos-deck.agent;

  listen =
    let
      endpoint = ps.listen s 8650;
      address = if lib.hasInfix ":" endpoint.address then "[${endpoint.address}]" else endpoint.address;
    in
    "${address}:${toString endpoint.port}";

  # Runtime secrets: name -> path on the host, read through LoadCredential.
  credentials = lib.filterAttrs (_: path: path != null) {
    forgejo-token = if cfg.forgejo != null then cfg.forgejo.tokenFile else null;
    github-token = if cfg.github != null then cfg.github.tokenFile else null;
    ahd-token = if cfg.ahd != null then cfg.ahd.tokenFile else null;
  };
  credential =
    name: lib.optionalAttrs (credentials ? ${name}) { token_file = "${credentialDir}/${name}"; };
  nonNull = lib.filterAttrs (_: value: value != null);

  # Services come from the registry catalog (modules.service-catalog); owners that are not
  # dashboard hosts (a guest) are placed with `placement`.
  services = map (
    svc:
    let
      place = cfg.placement.${svc.host} or null;
      hasUnits = svc.units != [ ] || svc.variants != [ ];
    in
    nonNull {
      inherit (svc)
        id
        title
        kind
        url
        private
        ;
      host = if place != null then place.host else svc.host;
      agent = if place != null && place.agent != null then place.agent else null;
      # Always explicit: "" turns the reachability check off.
      probe = if svc.probe != null then svc.probe else "";
      ops = if hasUnits then svc.ops else [ ];
      inherit (svc) units variants;
    }
  ) (ps.catalog config);

  settings = {
    inherit listen;
    public_origin = ps.url s 8650;
    state_dir = stateDir;
    ui_dir = "${pkg}/share/hypermonitor/ui";
    timezone = if config.time.timeZone != null then config.time.timeZone else "UTC";
    auth = nonNull {
      trusted_proxies = cfg.trustedProxies;
      session_idle_hours = cfg.sessionIdleHours;
      session_max_days = cfg.sessionMaxDays;
    };
    ssh = {
      program = "${pkgs.openssh}/bin/ssh";
      identity = "${stateDir}/ssh/id_ed25519";
    };
    agents = lib.mapAttrs (_: a: nonNull { inherit (a) socket ssh; }) cfg.agents;
    hosts = map (
      h:
      nonNull {
        inherit (h)
          name
          agent
          optional
          gpu
          flake
          report
          ;
        wol = if h.wol != null then { inherit (h.wol) mac broadcast; } else null;
        suspend_unit = h.suspendUnit;
        poweroff_unit = h.poweroffUnit;
      }
    ) cfg.hosts;
    inherit services;
  }
  // lib.optionalAttrs (cfg.ingestListen != null) {
    ingest_listen = cfg.ingestListen;
    ingest_peers = cfg.ingestPeers;
  }
  // lib.optionalAttrs (cfg.briefRetentionDays != null) {
    brief.retention_days = cfg.briefRetentionDays;
  }
  // lib.optionalAttrs (cfg.prometheusUrl != null) { prometheus.url = cfg.prometheusUrl; }
  // lib.optionalAttrs (cfg.forgejo != null) {
    forgejo = {
      inherit (cfg.forgejo) url user owners;
    }
    // credential "forgejo-token";
  }
  // lib.optionalAttrs (cfg.github != null) {
    github = {
      inherit (cfg.github) user;
      public_only = cfg.github.publicOnly;
    }
    // credential "github-token";
  }
  // lib.optionalAttrs (cfg.ahd != null) {
    ahd = {
      inherit (cfg.ahd) url;
    }
    // credential "ahd-token";
  }
  // lib.optionalAttrs (cfg.hermes != null) { hermes = { inherit (cfg.hermes) url; }; };

  configToml = toml.generate "hypermonitor.toml" settings;
  configFile = pkgs.runCommand "hypermonitor-config-checked.toml" { } ''
    ${pkg}/bin/hypermonitor check-config ${configToml}
    cp ${configToml} "$out"
  '';

  # The bridges may reach the ingest listener on their interface, nothing else may.
  ingest =
    let
      m =
        if cfg.ingestListen != null then builtins.match "\\[?([^]]*)]?:([0-9]+)" cfg.ingestListen else null;
      address = if m != null then builtins.elemAt m 0 else "";
      port = if m != null then builtins.elemAt m 1 else "";
      family = a: if lib.hasInfix ":" a then "ip6" else "ip";
      wildcard = address == "0.0.0.0" || address == "::";
      daddr = lib.optionalString (!wildcard) " ${family address} daddr ${address}";
    in
    lib.concatMapStrings (
      peer:
      "iifname \"${cfg.ingestInterface}\" ${family peer} saddr ${peer}${daddr} tcp dport ${port} accept\n"
    ) cfg.ingestPeers;

  # The server's SSH identity for the agents of other hosts: generated once in the state
  # directory and logged, so the consumer can authorise it on those hosts' agent accounts.
  keygen = pkgs.writeShellScript "hypermonitor-keygen" ''
    set -eu
    key="$STATE_DIRECTORY/ssh/id_ed25519"
    if [ ! -e "$key" ]; then
      mkdir -p -m 0700 "$STATE_DIRECTORY/ssh"
      ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C "hypermonitor@${config.networking.hostName}" -f "$key"
    fi
    echo "hypermonitor SSH public key: $(cat "$key.pub")"
  '';
in
{
  config = lib.mkIf s.enabled {
    modules.hypermonitor-settings = settings;
    users.users.hypermonitor = {
      isSystemUser = true;
      group = "hypermonitor";
      description = "HyperMonitor dashboard";
    };
    users.groups.hypermonitor = { };

    # `sudo hypermonitor passwd --config /etc/hypermonitor/config.toml` sets the login password.
    environment.systemPackages = [ pkg ];
    environment.etc."hypermonitor/config.toml".source = configFile;
    networking.firewall.extraInputRules = lib.mkIf (
      cfg.ingestListen != null && cfg.ingestInterface != null
    ) ingest;

    systemd.services.hypermonitor = ps.afterNetworkOnline // {
      description = "HyperMonitor dashboard";
      wantedBy = [ "multi-user.target" ];
      environment.RUST_LOG = lib.mkDefault "info";
      serviceConfig = {
        ExecStartPre = keygen;
        ExecStart = "${pkg}/bin/hypermonitor serve --config ${configFile}";
        User = "hypermonitor";
        Group = "hypermonitor";
        # The same-host agent socket (operations through attos-deck-agent).
        SupplementaryGroups = lib.optional (agent.enable && agent.socketGroup != null) agent.socketGroup;
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        LoadCredential = lib.mapAttrsToList (credName: path: "${credName}:${path}") credentials;
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        UMask = "0077";
      };
    };
  };
}
