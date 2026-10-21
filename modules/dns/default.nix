{
  config,
  lib,
  pkgs,
  ps,
  ...
}:
let
  cfg = config.modules.dns;
  hosts = ps.hosts config;
  # Forgejo SSH is published only on these gateway addresses; HTTP and SSH share the hostname.
  sshAddresses =
    services:
    if (services.forgejo.enable or false) && services.forgejo.deploy then
      services.forgejo.sshAddresses
    else
      [ ];
  entries = lib.concatLists (
    lib.mapAttrsToList (
      hostname: services:
      let
        addresses =
          if services.ssh.enable or false then
            [ services.ssh.address ]
          else if services.wireguard-server.enable or false then
            [ (ps.require "modules.dns" "wireguardAddress" cfg.wireguardAddress) ]
          else
            lib.filter (
              address: sshAddresses services == [ ] || lib.elem address (sshAddresses services)
            ) cfg.ingressAddresses;
      in
      map (address: "${address} ${hostname}") addresses
    ) hosts
  );
  hostsFile = pkgs.writeText "dnsmasq-public-services" (lib.concatStringsSep "\n" entries + "\n");
in
{
  options.modules.dns = {
    enable = lib.mkEnableOption "shared dnsmasq records generated from public-services";
    listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ "127.0.0.1" ];
      description = "Consumer-selected dnsmasq listen addresses; firewall policy remains consumer-owned.";
    };
    ingressAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      description = "Consumer-owned ingress addresses used for ordinary service hostnames.";
    };
    wireguardAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Local DNS address for the WireGuard endpoint; required when it is registered.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.ingressAddresses != [ ]
          || lib.all (
            services: (services.ssh.enable or false) || (services.wireguard-server.enable or false)
          ) (lib.attrValues hosts);
        message = "modules.dns.ingressAddresses must be supplied for ordinary service hostnames.";
      }
    ]
    ++ lib.mapAttrsToList (hostname: services: {
      assertion =
        sshAddresses services == [ ]
        || lib.any (address: lib.elem address cfg.ingressAddresses) (sshAddresses services);
      message = "modules.public-services.${hostname}.forgejo.sshAddresses must include at least one modules.dns.ingressAddresses entry.";
    }) hosts;
    environment.etc."dnsmasq-public-services".source = hostsFile;
    services.dnsmasq = {
      enable = true;
      settings = {
        listen-address = lib.mkDefault cfg.listenAddresses;
        bind-dynamic = lib.mkDefault true;
        localise-queries = lib.mkDefault true;
        addn-hosts = [ "/etc/dnsmasq-public-services" ];
        server = lib.mkDefault [
          "1.1.1.1"
          "1.0.0.1"
        ];
        no-resolv = lib.mkDefault true;
        domain-needed = lib.mkDefault true;
        bogus-priv = lib.mkDefault true;
      };
    };
    systemd.services.dnsmasq = {
      inherit (ps.afterNetworkOnline) wants after;
      restartTriggers = [ hostsFile ];
    };
  };
}
