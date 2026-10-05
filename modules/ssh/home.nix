{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  sshDir = "${config.home.homeDirectory}/.ssh";
  sshConfig = pkgs.writeText "ssh-config" config.home.file.".ssh/config".text;
in
{
  config = lib.mkIf osConfig.modules.ssh.enable {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = lib.mkMerge [
        {
          "*" = lib.mapAttrs (_: lib.mkDefault) {
            ForwardAgent = false;
            AddKeysToAgent = "no";
            Compression = false;
            StrictHostKeyChecking = "accept-new";
            Port = 22;
            HashKnownHosts = false;
            UserKnownHostsFile = "~/.ssh/known_hosts";
            ControlMaster = "auto";
            ControlPersist = "10m";
            ControlPath = "~/.ssh/cm-%C";
            ServerAliveInterval = 30;
            ServerAliveCountMax = 3;
          };
          attofort = lib.mapAttrs (_: lib.mkDefault) {
            HostName = "attofort.attodao.cc";
            User = "attodao";
            IdentityFile = "~/.ssh/id_ed25519";
          };
          attobox = lib.mapAttrs (_: lib.mkDefault) {
            HostName = "attobox.attodao.cc";
            User = "attodao";
            IdentityFile = "~/.ssh/id_ed25519";
          };
          devcon = lib.mapAttrs (_: lib.mkDefault) {
            HostName = "dev.attodao.cc";
            User = "dev";
            IdentityFile = "~/.ssh/id_ed25519";
          };
          desktop = lib.mapAttrs (_: lib.mkDefault) {
            HostName = "desk.attodao.cc";
            User = "attodao";
            IdentityFile = "~/.ssh/id_ed25519";
          };
          git = lib.mapAttrs (_: lib.mkDefault) {
            header = "Host git git.attodao.cc";
            HostName = "git.attodao.cc";
            User = "git";
            IdentityFile = "~/.ssh/id_ed25519";
            IdentitiesOnly = true;
          };
          github = lib.mapAttrs (_: lib.mkDefault) {
            header = "Host github github.com";
            HostName = "github.com";
            User = "git";
            IdentityFile = "~/.ssh/id_ed25519";
            IdentitiesOnly = true;
          };
        }
        (builtins.removeAttrs osConfig.modules.ssh [ "enable" ])
      ];
    };

    # Keep a user-owned regular file, not a store symlink; keys/known_hosts stay unmanaged.
    home.file.".ssh/config".enable = false;
    home.activation.installSshConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.coreutils}/bin/install -d -m 700 ${lib.escapeShellArg sshDir}
      run ${pkgs.coreutils}/bin/install -m 600 ${sshConfig} ${lib.escapeShellArg "${sshDir}/config"}
    '';
  };
}
