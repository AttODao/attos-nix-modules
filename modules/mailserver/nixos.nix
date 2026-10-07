{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "mailserver";
  cfg = selected.cfg;
  require = field: ps.require "mailserver" field cfg.${field};
  root = require "dataDir";
  domains = require "domains";
  primary =
    if domains == [ ] then throw "mailserver.domains must not be empty." else builtins.head domains;
  accounts = lib.mapAttrs (
    _: account:
    if
      (account.hashedPassword or null) != null
      || ((account.hashedPasswordFile or null) == null && (account.passwordFile or null) == null)
      || (
        (account.hashedPasswordFile or null) != null && !ps.absolutePath.check account.hashedPasswordFile
      )
      || ((account.passwordFile or null) != null && !ps.absolutePath.check account.passwordFile)
    then
      throw "mailserver: account credentials must be supplied as absolute runtime path strings, never inline hashes or Nix path literals."
    else
      # The public option evaluates the upstream schema once; native accounts
      # must derive their internal read-only name again rather than receive it.
      builtins.removeAttrs account [ "name" ]
  ) (require "accounts");
  dkimDomains = lib.mapAttrs (
    _: domain:
    domain
    // {
      selectors = lib.mapAttrs (
        _: selector:
        if selector.keyFile != null && !ps.absolutePath.check selector.keyFile then
          throw "mailserver: DKIM keyFile must be an absolute runtime path string, never a Nix path literal or store path."
        else
          selector
      ) domain.selectors;
    }
  ) (require "dkimDomains");
  hashFiles = lib.concatLists (
    lib.mapAttrsToList (
      _: account:
      lib.filter (path: path != null) [
        (account.hashedPasswordFile or null)
        (account.passwordFile or null)
      ]
    ) accounts
  );
  mailUser = config.mailserver.storage.owner;
  mailGroup = config.mailserver.storage.group;
  acmeHost = config.mailserver.x509.useACMEHost;
in
{
  config = lib.mkMerge [
    { assertions = selected.assertions; }
    (lib.mkIf selected.enabled (
      lib.mkMerge [
        {
          mailserver = {
            enable = true;
            openFirewall = lib.mkDefault false;
            stateVersion = require "stateVersion";
            fqdn = lib.mkDefault selected.hostname;
            inherit domains accounts;
            systemDomain = lib.mkDefault primary;
            systemName = lib.mkDefault cfg.systemName;
            systemContact = lib.mkDefault "postmaster@${primary}";
            sendingFqdn = lib.mkDefault selected.hostname;
            x509.useACMEHost = lib.mkDefault selected.hostname;
            enableImap = lib.mkDefault true;
            enableSubmission = lib.mkDefault true;
            enableManageSieve = lib.mkDefault true;
            storage.path = lib.mkDefault "${root}/vmail";
            indexDir = lib.mkDefault "${root}/index";
            dkim = {
              enable = lib.mkDefault true;
              keyDirectory = lib.mkDefault "${root}/dkim";
              domains = dkimDomains;
            };
          };
          systemd.tmpfiles.rules = [
            "d ${builtins.toJSON root} 0755 root root -"
            "d ${builtins.toJSON "${root}/vmail"} 0750 ${mailUser} ${mailGroup} -"
            "d ${builtins.toJSON "${root}/index"} 0750 ${mailUser} ${mailGroup} -"
            "d ${builtins.toJSON "${root}/dkim"} 0700 root root -"
          ];
          services.rspamd.locals."options.inc".text = lib.mkDefault ''
            dns {
              nameserver = [ "127.0.0.1:53" ];
            }
          '';
          systemd.services = {
            "acme-order-renew-${acmeHost}".unitConfig.RequiresMountsFor = [ root ];
            "acme-${acmeHost}".unitConfig.RequiresMountsFor = [ root ];
            dovecot.unitConfig.RequiresMountsFor = [ root ] ++ hashFiles;
            postfix.unitConfig.RequiresMountsFor = [ root ];
            rspamd = {
              unitConfig.RequiresMountsFor = [ root ];
              after = [ "kresd@1.service" ];
              requires = [ "kresd@1.service" ];
            };
            # Native postfix-tlspol needs a Unix socket as well as network sockets.
            postfix-tlspol.serviceConfig.RestrictAddressFamilies = lib.mkForce [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
          };
        }
        (lib.mkIf (cfg.acme.dnsProvider != null) {
          security.acme = {
            acceptTerms = lib.mkDefault cfg.acme.acceptTerms;
            defaults.email = lib.mkIf (cfg.acme.email != null) (lib.mkDefault cfg.acme.email);
            certs.${acmeHost} = {
              dnsProvider = lib.mkDefault cfg.acme.dnsProvider;
              environmentFile = lib.mkDefault (
                ps.require "mailserver.acme" "environmentFile" cfg.acme.environmentFile
              );
            };
          };
        })
        (lib.mkIf (cfg.relayHost != null) {
          services.postfix = {
            mapFiles.sasl_passwd = require "relayPasswordMap";
            settings.main = {
              relayhost = lib.mkDefault [ cfg.relayHost ];
              smtp_sasl_auth_enable = lib.mkDefault true;
              smtp_sasl_password_maps = lib.mkDefault [ "hash:/etc/postfix/sasl_passwd" ];
              smtp_sasl_security_options = lib.mkDefault "noanonymous";
              smtp_tls_security_level = lib.mkForce "encrypt";
            };
          };
          systemd.services.postfix.unitConfig.RequiresMountsFor = [ (require "relayPasswordMap") ];
        })
      ]
    ))
  ];
}
