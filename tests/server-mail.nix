{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  evaluate =
    modules:
    (t.evalSystem {
      users = [ ];
      inherit modules;
    }).config;
  base = evaluate [ ];
  mailModule = {
    modules.public-services."mail.example.test".mailserver = {
      enable = true;
      host = "nixos";
      domains = [ "example.test" ];
      accounts."alice@example.test" = {
        hashedPasswordFile = "/run/secrets/mail-alice";
        aliases = [ "postmaster@example.test" ];
      };
      stateVersion = 5;
      dataDir = "/srv/mail";
      dkimDomains."example.test".selectors.mail.keyFile = "/run/secrets/mail-dkim";
    };
    security.acme = {
      acceptTerms = true;
      defaults.email = "ops@example.test";
      certs."mail.example.test" = {
        dnsProvider = "cloudflare";
        credentialFiles.CF_DNS_API_TOKEN_FILE = "/run/secrets/cloudflare-token";
      };
    };
  };
  mail = evaluate [ mailModule ];
  groupware = evaluate [
    mailModule
    {
      modules.public-services."mail.example.test".groupware = {
        enable = true;
        host = "nixos";
        dataDir = "/srv/groupware";
      };
    }
  ];
  sameHostDependency = evaluate [
    (lib.recursiveUpdate mailModule {
      modules.public-services."mail.example.test".mailserver.enable = lib.mkDefault false;
    })
    {
      modules.public-services."mail.example.test".groupware = {
        enable = true;
        host = "nixos";
        dataDir = "/srv/groupware";
      };
    }
  ];
  remote = evaluate [
    {
      modules.public-services = {
        "remote-mail.example.test".mailserver = {
          enable = true;
          host = "remote";
          deploy = false;
        };
        "remote-webmail.example.test".groupware = {
          enable = true;
          host = "remote";
          deploy = false;
          backendUrl = "http://remote.internal:8080";
        };
      };
    }
  ];
  runnerModule = {
    modules.forgejo-actions-runner = {
      enable = true;
      dataDir = "/srv/runner";
      tokenFile = "/run/secrets/runner-env";
    };
    modules.public-services."forge.example.test".forgejo = {
      enable = true;
      host = "remote";
      deploy = false;
    };
  };
  runner = evaluate [ runnerModule ];
  runnerOverride = evaluate [
    runnerModule
    {
      services.gitea-actions-runner.instances.forgejo = {
        name = "consumer-runner";
        url = "https://other-forge.example.test";
      };
    }
  ];
  relay = evaluate [
    mailModule
    {
      modules.public-services."mail.example.test".mailserver = {
        relayHost = "[smtp.example.test]:587";
        relayPasswordMap = "/run/secrets/smtp-sasl";
      };
    }
  ];
  standardOverride = evaluate [
    mailModule
    { mailserver.storage.path = "/srv/other-mail"; }
  ];
  inlineHash = builtins.tryEval (
    builtins.deepSeq
      (evaluate [
        mailModule
        {
          modules.public-services."mail.example.test".mailserver.accounts."alice@example.test" = {
            hashedPassword = "not-a-runtime-file";
            hashedPasswordFile = lib.mkForce null;
          };
        }
      ]).mailserver.accounts
      true
  );
  storeKey =
    builtins.tryEval
      (evaluate [
        mailModule
        {
          modules.public-services."mail.example.test".mailserver.dkimDomains."example.test".selectors.mail.keyFile =
            lib.mkForce ../AGENTS.md;
        }
      ]).mailserver.dkim.domains."example.test".selectors.mail.keyFile;
  badTarget = evaluate [
    {
      modules.public-services."webmail.example.test" = {
        mailserver.enable = lib.mkForce false;
        groupware = {
          enable = true;
          host = "nixos";
          dataDir = "/srv/groupware";
        };
      };
    }
  ];
in
assert base.home-manager.users == { } && !base.mailserver.enable && !base.services.radicale.enable;
assert !base.modules.forgejo-actions-runner.enable && !base.virtualisation.docker.enable;
assert !(base.systemd.services ? radicale-users) && !(base.systemd.services ? gitea-runner-forgejo);
assert lib.all (a: a.assertion) mail.assertions && mail.home-manager.users == { };
assert mail.mailserver.fqdn == "mail.example.test" && mail.mailserver.stateVersion == 5;
assert
  mail.mailserver.storage.path == "/srv/mail/vmail" && mail.mailserver.indexDir == "/srv/mail/index";
assert
  mail.mailserver.accounts."alice@example.test".hashedPasswordFile == "/run/secrets/mail-alice";
assert mail.mailserver.accounts."alice@example.test".name == "alice@example.test";
assert builtins.deepSeq mail.mailserver.accounts true;
assert
  mail.mailserver.dkim.domains."example.test".selectors.mail.keyFile == "/run/secrets/mail-dkim";
assert !mail.mailserver.openFirewall && mail.networking.firewall.allowedTCPPorts == [ ];
assert mail.mailserver.x509.useACMEHost == "mail.example.test";
assert lib.elem "AF_UNIX"
  mail.systemd.services.postfix-tlspol.serviceConfig.RestrictAddressFamilies;
assert
  lib.all (a: a.assertion) groupware.assertions
  && groupware.services.roundcube.enable
  && groupware.services.radicale.enable;
assert sameHostDependency.modules.public-services."mail.example.test".mailserver.enable;
assert
  groupware.services.radicale.settings.auth.htpasswd_filename == "/srv/groupware/secrets/users";
assert
  groupware.services.radicale.settings.storage.filesystem_folder == "/srv/groupware/collections";
assert lib.elem "radicale-users.service" groupware.systemd.services.radicale.requires;
assert !groupware.services.nginx.virtualHosts."mail.example.test".forceSSL;
assert
  !remote.mailserver.enable && !remote.services.radicale.enable && !remote.services.roundcube.enable;
assert
  runner.modules.docker.enable && runner.services.gitea-actions-runner.instances.forgejo.enable;
assert
  runner.services.gitea-actions-runner.instances.forgejo.tokenFile == "/run/secrets/runner-env";
assert
  runner.systemd.services.gitea-runner-forgejo.serviceConfig.BindPaths
  == [ "/srv/runner:/var/lib/gitea-runner/forgejo" ];
assert !runner.systemd.services.gitea-runner-forgejo.serviceConfig.DynamicUser;
assert runner.services.gitea-actions-runner.instances.forgejo.name == runner.networking.hostName;
assert runner.services.gitea-actions-runner.instances.forgejo.url == "https://forge.example.test";
assert runnerOverride.services.gitea-actions-runner.instances.forgejo.name == "consumer-runner";
assert
  runnerOverride.services.gitea-actions-runner.instances.forgejo.url
  == "https://other-forge.example.test";
assert relay.services.postfix.mapFiles.sasl_passwd == "/run/secrets/smtp-sasl";
assert relay.services.postfix.settings.main.smtp_tls_security_level == "encrypt";
assert standardOverride.mailserver.storage.path == "/srv/other-mail";
assert !inlineHash.success && !storeKey.success;
assert lib.any (a: !a.assertion && lib.hasInfix "same hostname" a.message) badTarget.assertions;
true
