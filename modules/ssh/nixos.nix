{ config, lib, ... }:
{
  config = lib.mkIf config.modules.ssh.enable {
    # Avoid the root-owned store Include rejected by unprivileged SSH clients.
    programs.ssh.systemd-ssh-proxy.enable = lib.mkDefault false;
  };
}
