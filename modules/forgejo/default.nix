{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "forgejo";
  nullableString =
    description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      inherit description;
    };
in
{
  options.modules = ps.moduleOptions "forgejo" (
    ps.common "shared Forgejo service"
    // {
      dataDir = ps.pathOption "Persistent service root keeping the official image layout: forgejo/gitea (app data), forgejo/git (repositories, LFS) and forgejo/ssh (host keys).";
      mailAddress = nullableString "Forgejo sender and envelope-from address.";
      mailHost = nullableString "SMTP server hostname (port 587, STARTTLS); authentication goes through services.forgejo.settings.mailer.USER and services.forgejo.secrets.mailer.PASSWD.";
      sshAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = [ ];
        description = "Gateway IP addresses on which Traefik publishes Forgejo SSH port 22; empty publishes on all addresses. Local DNS then returns only the ingress addresses in this list for the hostname.";
      };
      trustedProxies = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = [
          "127.0.0.0/8"
          "::1/128"
        ];
        description = "IP addresses or CIDR ranges whose X-Forwarded-* headers Forgejo trusts (REVERSE_PROXY_TRUSTED_PROXIES). A public owner lists the gateway address that connects to backendUrl; the loopback default trusts nothing else.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled (
      let
        cfg = s.cfg;
        root = "${ps.require "forgejo" "dataDir" cfg.dataDir}/forgejo";
        mailEnabled = !s.standalone || cfg.mailHost != null || cfg.mailAddress != null;
        listen =
          if s.standalone then
            {
              address = "127.0.0.1";
              port = "3000";
            }
          else
            ps.backendEndpoint s;
        sshPort = if s.standalone then 2222 else 22;
        hostKeys = map (type: "${root}/ssh/ssh_host_${type}_key") [
          "ed25519"
          "rsa"
          "ecdsa"
        ];
      in
      {
        services.forgejo = {
          enable = true;
          # The image tracks the current release, not LTS; a downgrade would break the database.
          package = lib.mkDefault pkgs.forgejo;
          database = {
            type = "postgres";
            createDatabase = true;
          };
          # Keep the official image layout so repositories, LFS, avatars and attachments stay put.
          stateDir = "${root}/gitea";
          repositoryRoot = "${root}/git/repositories";
          lfs = {
            enable = true;
            contentDir = "${root}/git/lfs";
          };
          settings = lib.mapAttrsRecursive (_: lib.mkDefault) {
            server = {
              APP_DATA_PATH = "${root}/gitea";
              DOMAIN = s.hostname;
              ROOT_URL = "${ps.url s 3000}/";
              HTTP_ADDR = listen.address;
              HTTP_PORT = lib.toInt listen.port;
              SSH_DOMAIN = s.hostname;
              SSH_PORT = sshPort;
              # The built-in server replaces the image's OpenSSH and keeps its host keys and git@ user.
              START_SSH_SERVER = true;
              BUILTIN_SSH_SERVER_USER = "git";
              SSH_LISTEN_HOST = listen.address;
              SSH_LISTEN_PORT = if s.standalone then 2222 else ps.forgejoSshBackendPort;
              SSH_SERVER_HOST_KEYS = lib.concatStringsSep "," hostKeys;
              OFFLINE_MODE = true;
            };
            security = {
              REVERSE_PROXY_LIMIT = 1;
              REVERSE_PROXY_TRUSTED_PROXIES = lib.concatStringsSep "," cfg.trustedProxies;
            };
            actions = {
              ENABLED = true;
              DEFAULT_ACTIONS_URL = "https://data.forgejo.org";
            };
            mailer = {
              ENABLED = mailEnabled;
            }
            // lib.optionalAttrs mailEnabled {
              PROTOCOL = "smtp+starttls";
              SMTP_ADDR = ps.require "forgejo" "mailHost" cfg.mailHost;
              SMTP_PORT = 587;
              FROM = ps.require "forgejo" "mailAddress" cfg.mailAddress;
              ENVELOPE_FROM = cfg.mailAddress;
            };
          };
        };
        systemd.services.forgejo = {
          unitConfig.RequiresMountsFor = [ root ];
          # A public owner binds the backendUrl address, which must exist first.
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
        };
        networking.firewall = ps.backendFirewall config s [ ps.forgejoSshBackendPort ];
      }
    ))
  ];
}
