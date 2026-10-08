{ lib, options, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  nullable =
    type: description:
    lib.mkOption {
      type = lib.types.nullOr type;
      default = null;
      inherit description;
    };
in
{
  imports = [
    ./nixos.nix
    (builtins.fetchTarball {
      url = "https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/archive/2c3a8c4e36ab8190010f9f104e48d042cc65b05f/nixos-mailserver-2c3a8c4e36ab8190010f9f104e48d042cc65b05f.tar.gz";
      sha256 = "sha256-jnU8wDRoMIUxuT0AgGYxqPucIf3cOAwWrmB23xarCXI=";
    })
  ];

  options.modules = ps.moduleOptions "mailserver" (
    ps.common "shared simple-nixos-mailserver integration"
    // {
      domains = nullable (lib.types.listOf lib.types.nonEmptyStr) "Consumer-owned mail domains; the first is the system domain.";
      backendAddress = nullable lib.types.nonEmptyStr "Native mail upstream address reachable by Traefik (without a port); required on the gateway when mail forwarding is enabled.";
      tcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [
          25
          143
          465
          587
          993
          4190
        ];
        description = "Mail protocol ports forwarded by Traefik; align with any standard mailserver protocol overrides.";
      };
      # Use the upstream account schema, including aliases and runtime hashedPasswordFile.
      accounts =
        nullable (options.mailserver.accounts.type or lib.types.attrs)
          "Accounts using the standard upstream mailserver.accounts interface. Supply runtime hashedPasswordFile paths, not inline credentials.";
      stateVersion = nullable lib.types.int "Existing simple-nixos-mailserver stateVersion; the consumer owns migrations.";
      systemName = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "Mail system";
        description = "Human-readable mail system name.";
      };
      acme = {
        dnsProvider = nullable lib.types.nonEmptyStr "Optional DNS-01 provider for the mail hostname certificate; null leaves native ACME configuration untouched.";
        environmentFile = ps.pathOption "Runtime ACME environment file for the DNS provider, never credential contents.";
        email = nullable lib.types.nonEmptyStr "Contact email used when the mail DNS-01 provider is configured.";
        acceptTerms = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Accept ACME terms when configuring the mail DNS-01 certificate.";
        };
      };
      dataDir = ps.pathOption "Mail data directory containing vmail, index and dkim subdirectories.";
      dkimDomains = nullable (options.mailserver.dkim.domains.type or lib.types.attrs
      ) "Upstream DKIM domain/selector definitions with consumer-provided runtime keyFile paths.";
      relayHost = nullable lib.types.nonEmptyStr "Optional upstream Postfix relayhost, for example [smtp.example.org]:587. Null sends directly.";
      relayPasswordMap = ps.pathOption "Runtime Postfix SASL password map; required only when relayHost is supplied.";
    }
  );
}
