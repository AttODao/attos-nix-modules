{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.wireguard-client;
  tunnels = lib.imap0 (index: name: {
    inherit name;
    credential = "tunnel-${toString index}";
    path = cfg.tunnels.${name};
  }) (builtins.attrNames cfg.tunnels);
  metadata = pkgs.writeText "wireguard-client-tunnels.json" (
    builtins.toJSON (map (tunnel: { inherit (tunnel) name credential; }) tunnels)
  );
  python = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  command = "${lib.getExe python} ${./import-tunnels.py}";
in
{
  config = lib.mkIf cfg.enable {
    # A normal assignment deliberately exposes an explicitly false consumer value.
    networking.networkmanager.enable = true;

    systemd.services.wireguard-client-import = lib.mkIf (cfg.tunnels != { }) {
      description = "Import runtime WireGuard profiles into NetworkManager";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "NetworkManager.service"
      ]
      ++ lib.optional (cfg.secretService != null) cfg.secretService;
      after = [ "NetworkManager.service" ] ++ lib.optional (cfg.secretService != null) cfg.secretService;
      partOf = [ "NetworkManager.service" ];
      path = [ pkgs.networkmanager ];
      environment = {
        LC_ALL = "C";
        # NM's typelib embeds the absolute libnm path; no LD_LIBRARY_PATH needed.
        GI_TYPELIB_PATH = "${pkgs.networkmanager}/lib/girepository-1.0";
      };

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
        RuntimeDirectory = "wireguard-client";
        RuntimeDirectoryMode = "0700";
        # Retain ownership records if NM deletion fails, so a later start can retry.
        RuntimeDirectoryPreserve = "yes";
        UMask = "0077";
        LoadCredential = map (tunnel: "${tunnel.credential}:${tunnel.path}") tunnels;
      };

      script = ''
        exec ${command} start /run/wireguard-client ${metadata}
      '';
      # ExecStopPost also runs after a failed or interrupted ExecStart.
      postStop = ''
        exec ${command} stop /run/wireguard-client
      '';
    };
  };
}
