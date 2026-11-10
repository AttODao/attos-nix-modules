# Values for options that a feature requires when enabled, used by the checks in ./default.nix.
# A new module needs an entry only if it has required options. All values are placeholders:
# the checks only evaluate, so paths need not exist and nothing is built.
#   modules.<name>   NixOS module added to the module-<name> system
#   services.<name>  attributes merged into the public registry record of a public service
#                    (modules.public-services."<name>.<hostName>.example".<name>)
#   home.<name>      Home Manager module added to the standalone home-manager-<name> configuration
{ lib, hostName }:
let
  fqdn = name: "${name}.${hostName}.example";
  cursor = { pkgs, ... }: { modules.desktop-theme.cursor = pkgs.emptyFile; };
  ytdlSub = {
    dataDir = "/srv/ytdl-sub";
    cookieFile = "/srv/ytdl-sub/cookie.txt";
    subscriptions.test."Jellyfin TV Show by Date".Test = "https://www.youtube.com/@example";
  };
  services = {
    attic = {
      backendUrl = "http://127.0.0.1:8080";
      dataDir = "/srv/attic";
      environmentFile = "/run/secrets/atticd.env";
    };
    attos-hoyo-dashboard = {
      backendUrl = "http://127.0.0.1:8082";
      dataDir = "/srv/attos-hoyo-dashboard";
      environmentFile = "/run/secrets/attos-hoyo-dashboard.env";
      timezoneOffset = "+09:00";
    };
    code-server = {
      backendUrl = "http://127.0.0.1:4444";
      environmentFile = "/run/secrets/code-server.env";
    };
    forgejo = {
      backendUrl = "http://127.0.0.1:3000";
      dataDir = "/srv/forgejo";
      mailHost = fqdn "mail";
      mailAddress = "forgejo@${fqdn "mail"}";
    };
    groupware = {
      backendUrl = "http://127.0.0.1:80";
      dataDir = "/srv/radicale";
    };
    headscale = {
      backendUrl = "http://127.0.0.1:8085";
      baseDomain = "tailnet.${hostName}.example";
    };
    hermes = {
      backendUrl = "http://127.0.0.1:9119";
      dataDir = "/srv/hermes";
      private = true;
    };
    immich = {
      backendUrl = "http://127.0.0.1:2283";
      dataDir = "/srv/immich";
    };
    jellyfin = {
      backendUrl = "http://127.0.0.1:8096";
      dataDir = "/srv/jellyfin";
      mediaDir = "/srv/media";
    };
    karakeep = {
      backendUrl = "http://127.0.0.1:3001";
      dataDir = "/srv/karakeep";
      environmentFile = "/run/secrets/karakeep.env";
    };
    mailserver = {
      domains = [ "${hostName}.example" ];
      backendAddress = "127.0.0.1";
      dataDir = "/srv/mailserver";
      stateVersion = 5;
      accounts."tester@${hostName}.example".hashedPasswordFile = "/run/secrets/mail-password-hash";
      dkimDomains."${hostName}.example".selectors.mail.keyFile = "/run/secrets/dkim.key";
      acme = {
        acceptTerms = true;
        email = "postmaster@${hostName}.example";
        dnsProvider = "cloudflare";
        environmentFile = "/run/secrets/acme.env";
      };
    };
    mcsmanager = {
      backendUrl = "http://127.0.0.1:23333";
      daemonBackendUrl = "http://127.0.0.1:24444";
      dataDir = "/srv/mcsmanager";
      webUser = "mcs-web";
      daemonUser = "mcs-daemon";
      group = "mcsmanager";
      daemonKeyFile = "/run/secrets/mcsmanager-daemon-key";
      private = true;
    };
    opencloud = {
      backendUrl = "http://127.0.0.1:9200";
      dataDir = "/srv/opencloud";
      environmentFile = "/run/secrets/opencloud.env";
    };
    searxng = {
      backendUrl = "http://127.0.0.1:8081";
      environmentFile = "/run/secrets/searxng.env";
    };
    strata = {
      backendUrl = "http://127.0.0.1:8080";
      user = "tester";
      dataDir = "/srv/strata";
      apiKeyFile = "/run/secrets/strata-api-key";
      flavor = "rocm-gfx110x";
    };
    vaultwarden = {
      backendUrl = "http://127.0.0.1:8000";
      dataDir = "/srv/vaultwarden";
      environmentFile = "/run/secrets/vaultwarden.env";
    };
  };
in
{
  inherit services;

  modules = {
    attos-jobs.modules.attos-jobs.socketGroup = "wheel";
    # The bridge listens on the SSH address registered for the same hostname.
    ccpocket.modules.public-services.${fqdn "ccpocket"}.ssh = {
      enable = true;
      host = hostName;
      address = "127.0.0.1";
    };
    cloudflare-ddns.modules.cloudflare-ddns = {
      records = [ (fqdn "ddns") ];
      environmentFile = "/run/secrets/cloudflare.env";
    };
    cloudflare-public-cnames.modules.cloudflare-public-cnames = {
      target = fqdn "gateway";
      environmentFile = "/run/secrets/cloudflare.env";
    };
    desktop-theme = cursor;
    forgejo-actions-runner.modules.forgejo-actions-runner = {
      uuid = "00000000-0000-0000-0000-000000000000";
      tokenFile = "/run/secrets/forgejo-runner-token";
      url = "https://${fqdn "forgejo"}";
    };
    greeter = cursor;
    # Groupware needs the Mailserver of the same hostname on the same host.
    groupware.modules.public-services.${fqdn "groupware"}.mailserver = {
      enable = true;
      host = hostName;
    }
    // services.mailserver;
    # The service accounts are the consumer's.
    hermes = {
      users.users.hermes = {
        isSystemUser = true;
        group = "hermes";
      };
      users.groups.hermes = { };
    };
    hermes-desktop.modules.hermes-desktop.ssh = "tester@${fqdn "hermes"}";
    # A public Jellyfin enables ytdl-sub on the same host.
    jellyfin.modules.ytdl-sub = ytdlSub;
    # login-pin orders its rule before NixOS' early pam_unix rule (unix-early), which exists only
    # when e.g. gnome-keyring or zfs is enabled; the desktops using it have gnome-keyring.
    login-pin = {
      modules.login-pin = {
        user = "tester";
        pinDatabaseFile = "/etc/security/login-pin/pins.db";
      };
      services.gnome.gnome-keyring.enable = true;
    };
    mcsmanager = {
      users.users = lib.genAttrs [ "mcs-web" "mcs-daemon" ] (_: {
        isSystemUser = true;
        group = "mcsmanager";
      });
      users.groups.mcsmanager = { };
    };
    open-terminal = {
      modules.open-terminal = {
        dataDir = "/srv/open-terminal";
        environmentFile = "/run/secrets/open-terminal.env";
        uid = 1000;
        gid = 100;
      };
      virtualisation.oci-containers.containers.open-terminal.environment.OPEN_TERMINAL_CORS_ALLOWED_ORIGINS =
        "http://localhost";
    };
    opencloud-client.modules.opencloud-client.serverUrl = "https://${fqdn "opencloud"}";
    traefik.modules.traefik.environmentFile = "/run/secrets/traefik.env";
    ytdl-sub.modules.ytdl-sub = ytdlSub;
  };

  home = {
    desktop-theme = cursor;
    hermes-desktop.modules.hermes-desktop.ssh = "tester@${fqdn "hermes"}";
    opencloud-client.modules.opencloud-client.serverUrl = "https://${fqdn "opencloud"}";
  };
}
