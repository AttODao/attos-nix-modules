{
  config,
  lib,
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
  ownership =
    description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      inherit description;
    };
in
{
  options.modules = ps.moduleOptions "forgejo" (
    ps.common "shared Forgejo service"
    // {
      dataDir = ps.pathOption "Persistent service root containing forgejo/ and postgres/ directories.";
      environmentFile = ps.pathOption "Runtime environment file for Forgejo and PostgreSQL, including database credentials.";
      userUid = ownership "Caller-managed Forgejo UID, supplied to the image as USER_UID; no account is created.";
      userGid = ownership "Caller-managed Forgejo GID, supplied to the image as USER_GID; no group is created.";
      mailAddress = nullableString "Forgejo sender and envelope-from address.";
      mailHost = nullableString "SMTP server hostname; port and protocol can be overridden through standard OCI environment settings.";
      sshAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = [ ];
        description = "Gateway IP addresses on which Traefik publishes Forgejo SSH port 22; empty publishes on all addresses. Local DNS then returns only the ingress addresses in this list for the hostname.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled (
      let
        cfg = s.cfg;
        root = ps.require "forgejo" "dataDir" cfg.dataDir;
        environmentFile = ps.require "forgejo" "environmentFile" cfg.environmentFile;
        uid = toString (ps.require "forgejo" "userUid" cfg.userUid);
        gid = toString (ps.require "forgejo" "userGid" cfg.userGid);
        mailEnabled = !s.standalone || cfg.mailHost != null || cfg.mailAddress != null;
        mailAddress = if mailEnabled then ps.require "forgejo" "mailAddress" cfg.mailAddress else null;
        mailHost = if mailEnabled then ps.require "forgejo" "mailHost" cfg.mailHost else null;
        sshPort = if s.standalone then 2222 else 22;
        forgejoDataRoot = "${root}/forgejo";
        forgejoDbRoot = "${root}/postgres";
        mounts = {
          unitConfig.RequiresMountsFor = [
            root
            environmentFile
          ];
        };
      in
      {
        modules.docker.enable = true;
        modules.docker.networks.forgejo = { };
        modules.swarm.enable = lib.mkIf (!s.standalone) true;
        assertions = [
          {
            assertion = cfg.userUid != null && cfg.userGid != null;
            message = "Forgejo requires consumer-owned userUid and userGid for local deployment.";
          }
        ];

        systemd.tmpfiles.settings."10-forgejo" = {
          ${root}.d = {
            mode = lib.mkDefault "0755";
            user = lib.mkDefault "root";
            group = lib.mkDefault "root";
          };
          ${forgejoDataRoot}.d = {
            mode = lib.mkDefault "0755";
            user = lib.mkDefault "root";
            group = lib.mkDefault "root";
          };
          ${forgejoDbRoot}.d = {
            mode = lib.mkDefault "0700";
            user = lib.mkDefault "999";
            group = lib.mkDefault "999";
          };
        };

        systemd.services = {
          docker-forgejo-db = mounts;
          docker-forgejo = lib.mkMerge [
            mounts
            {
              wants = [ (ps.networkUnit s) ];
              after = [ (ps.networkUnit s) ];
            }
          ];
        };

        virtualisation.oci-containers.containers = {
          forgejo-db = {
            image = lib.mkDefault "postgres:14.24@sha256:c2427de38f998489d36de7ca3553db2134872c400f2b08be4b824e5c50e4d619";
            environment = lib.mapAttrs (_: lib.mkDefault) {
              POSTGRES_USER = "forgejo";
              POSTGRES_DB = "forgejo";
            };
            environmentFiles = lib.mkDefault [ environmentFile ];
            autoRemoveOnStop = lib.mkDefault false;
            extraOptions = lib.mkDefault [ "--restart=always" ];
            volumes = lib.mkDefault [ "${forgejoDbRoot}:/var/lib/postgresql/data" ];
            networks = lib.mkDefault [ "forgejo" ];
          };
          forgejo = {
            image = lib.mkDefault "codeberg.org/forgejo/forgejo:16.0.5@sha256:cf5f5ae6acf2ababca0ee3d255705b83a47f35b25e07fc931d694d60664053fe";
            environment = lib.mapAttrs (_: lib.mkDefault) (
              {
                USER_UID = uid;
                USER_GID = gid;
                FORGEJO__database__DB_TYPE = "postgres";
                FORGEJO__database__HOST = "forgejo-db:5432";
                FORGEJO__database__NAME = "forgejo";
                FORGEJO__database__USER = "forgejo";
                FORGEJO__actions__ENABLED = "true";
                FORGEJO__actions__DEFAULT_ACTIONS_URL = "https://data.forgejo.org";
                FORGEJO__mailer__ENABLED = lib.boolToString mailEnabled;
                FORGEJO__mailer__PROTOCOL = "smtp+starttls";
                FORGEJO__mailer__SMTP_PORT = "587";
                FORGEJO__server__DOMAIN = s.hostname;
                FORGEJO__server__ROOT_URL = "${ps.url s 3000}/";
                FORGEJO__server__SSH_DOMAIN = s.hostname;
                FORGEJO__server__SSH_PORT = toString sshPort;
              }
              // lib.optionalAttrs (mailAddress != null) {
                FORGEJO__mailer__FROM = mailAddress;
                FORGEJO__mailer__ENVELOPE_FROM = mailAddress;
              }
              // lib.optionalAttrs (mailHost != null) {
                FORGEJO__mailer__SMTP_ADDR = mailHost;
              }
            );
            environmentFiles = lib.mkDefault [ environmentFile ];
            autoRemoveOnStop = lib.mkDefault false;
            extraOptions = lib.mkDefault [ "--restart=always" ];
            # Published SSH is forwarded by the Traefik gateway over the backend overlay.
            ports = lib.mkDefault (
              lib.optionals s.standalone [
                "127.0.0.1:${toString sshPort}:22"
                "127.0.0.1:3000:3000"
              ]
            );
            volumes = lib.mkDefault [
              "${forgejoDataRoot}:/data"
              "/etc/localtime:/etc/localtime:ro"
            ];
            dependsOn = lib.mkDefault [ "forgejo-db" ];
            networks = lib.mkDefault [
              "forgejo"
              (ps.network s)
            ];
          };
        };
      }
    ))
  ];
}
