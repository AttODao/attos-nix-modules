{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib pkgs;
  evaluate =
    modules:
    (t.evalSystem {
      users = [ ];
      inherit modules;
    }).config;
  base = evaluate [ ];
  fcitx = t.hmFor [
    {
      modules.fcitx5 = {
        enable = true;
        keyboardLayout = "us";
      };
    }
  ];
  runnerModule = {
    boot.isContainer = lib.mkForce false;
    boot.loader.grub.enable = false;
    virtualisation.incus.agent.enable = true;
    modules.forgejo-actions-runner = {
      enable = true;
      dynamicUser = true;
      dataDir = "/var/lib/gitea-runner/forgejo";
      tokenFile = "/run/secrets/runner.env";
      requiresMountsFor = [ "/srv/data" ];
    };
    modules.public-services."forge.example.test".forgejo = {
      enable = true;
      host = "remote";
      deploy = false;
      backendUrl = "http://forgejo.external:8080";
    };
  };
  runner = evaluate [ runnerModule ];
  badRunner = evaluate [
    runnerModule
    { modules.forgejo-actions-runner.dataDir = lib.mkForce "/srv/runner"; }
  ];
  mail = evaluate [
    {
      modules.public-services."mail.example.test" = {
        mailserver = {
          enable = true;
          host = "nixos";
          domains = [ "example.test" ];
          accounts."alice@example.test".hashedPasswordFile = "/run/secrets/alice";
          stateVersion = 5;
          systemName = "Example mail";
          dataDir = "/srv/mail";
          dkimDomains."example.test".selectors.mail.keyFile = "/run/secrets/dkim";
          acme = {
            acceptTerms = true;
            email = "ops@example.test";
            dnsProvider = "cloudflare";
            environmentFile = "/run/secrets/acme.env";
          };
        };
        groupware = {
          enable = true;
          host = "nixos";
          dataDir = "/srv/dav";
          productName = "Alice's \\ Mail";
        };
      };
    }
  ];
  apps = evaluate [
    {
      modules.swarm = {
        role = "manager";
        advertiseAddress = "10.250.0.1";

      };
      modules.public-services = {
        "vault.example.test".vaultwarden = {
          enable = true;
          host = "nixos";
          dataDir = "/srv/vault";
          environmentFile = "/run/secrets/vault.env";
          signupsAllowed = true;
          extraHosts."mail.example.test" = "10.250.0.2";
        };
        "keep.example.test".karakeep = {
          enable = true;
          host = "nixos";
          dataDir = "/srv/keep";
          environmentFile = "/run/secrets/keep.env";
          dataUid = 1000;
          dataGid = 1000;
          environment = {
            OPENAI_BASE_URL = "http://10.250.0.1:11434/v1";
            INFERENCE_TEXT_MODEL = "test-model";
            LOG_LEVEL = "debug";
          };
        };
      };
      modules.ytdl-sub = {
        enable = true;
        dataDir = "/srv/media";
        cookieFile = "/run/secrets/cookie";
        startConditionFile = "/srv/media/config/subscriptions-youtube.yaml";
        subscriptionFiles = {
          youtube = pkgs.writeText "youtube.yaml" "{}\n";
          twitch = pkgs.writeText "twitch.yaml" "{}\n";
        };
        uid = 1000;
        gid = 1000;
      };
    }
  ];
in
assert fcitx.i18n.inputMethod.fcitx5.settings.inputMethod."Groups/0/Items/1".Layout == "us";
assert !base.modules.forgejo-actions-runner.enable;
assert !(base.systemd.services ? gitea-runner-forgejo);
assert !(base.users.users ? gitea-runner);
assert runner.systemd.services.gitea-runner-forgejo.serviceConfig.DynamicUser;
assert (runner.systemd.services.gitea-runner-forgejo.serviceConfig.BindPaths or [ ]) == [ ];
assert !(runner.users.users ? gitea-runner);
assert (runner.systemd.tmpfiles.settings."10-forgejo-actions-runner" or { }) == { };
assert
  runner.systemd.services.gitea-runner-forgejo.unitConfig.RequiresMountsFor == [
    "/var/lib/gitea-runner/forgejo"
    "/srv/data"
  ];
assert lib.all (a: a.assertion) runner.assertions;
assert !lib.all (a: a.assertion) badRunner.assertions;
assert mail.mailserver.systemName == "Example mail";
assert mail.security.acme.acceptTerms;
assert mail.security.acme.defaults.email == "ops@example.test";
assert mail.security.acme.certs."mail.example.test".dnsProvider == "cloudflare";
assert mail.security.acme.certs."mail.example.test".environmentFile == "/run/secrets/acme.env";
assert
  mail.systemd.services."acme-mail.example.test".unitConfig.RequiresMountsFor == [ "/srv/mail" ];
assert lib.hasInfix "Alice\\'s \\\\ Mail" mail.services.roundcube.extraConfig;
assert builtins.deepSeq mail.mailserver.accounts true;
assert lib.all (a: a.assertion) mail.assertions;
assert
  apps.virtualisation.oci-containers.containers.vaultwarden.extraOptions == [
    "--restart=unless-stopped"
    "--add-host=mail.example.test:10.250.0.2"
  ];
assert
  apps.virtualisation.oci-containers.containers.karakeep.environment.INFERENCE_TEXT_MODEL
  == "test-model";
assert apps.virtualisation.oci-containers.containers.karakeep.environment.LOG_LEVEL == "debug";
assert
  apps.virtualisation.oci-containers.containers.karakeep.environment.NEXTAUTH_URL
  == "https://keep.example.test";
assert
  apps.systemd.services.docker-ytdl-sub.unitConfig.ConditionPathExists
  == "/srv/media/config/subscriptions-youtube.yaml";
assert
  apps.virtualisation.oci-containers.containers.vaultwarden.environment.SIGNUPS_ALLOWED == "true";
assert
  !(
    apps.virtualisation.oci-containers.containers.vaultwarden.environment ? SIGNUPS_DOMAINS_WHITELIST
  );
assert lib.hasInfix " true" apps.systemd.services.docker-vaultwarden.preStart;
assert !(apps.virtualisation.oci-containers.containers.vaultwarden.environment ? ADMIN_TOKEN);
assert lib.all (a: a.assertion) apps.assertions;
true
