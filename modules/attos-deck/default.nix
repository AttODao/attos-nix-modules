{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  tomlValue = (pkgs.formats.toml { }).type;
  cfg = config.modules.attos-deck;
in
{
  imports = [ ./nixos.nix ];

  options.modules.attos-deck = {
    enable = lib.mkEnableOption "attos-deck Stream Deck MK.2 status controller (system service)";
    settings = mkOption {
      type = tomlValue;
      default = { };
      description = "attos-deck config.toml. Hosts, agents, sources and home keys belong to the consumer; the shared defaults (timezone from time.timeZone, state directory, SSH client and identity, static CJK font) are merged recursively and lists replace. Checked with `attos-deck check-config` at build time.";
    };
    credentials = mkOption {
      type = types.attrsOf (types.strMatching "/[^[:space:]]+");
      default = { };
      example = {
        github-token = "/run/secrets/attos-deck/github-token";
      };
      description = "Runtime secret paths passed with systemd LoadCredential. Refer to them in settings as /run/credentials/attos-deck.service/<name>; their contents never enter the Nix store.";
    };
    agent = {
      enable = lib.mkEnableOption "attos-deck-agent, a socket-activated root helper that runs only allow-listed systemctl operations for attos-deck";
      socketGroup = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        description = "Existing consumer group allowed to connect to /run/attos-deck-agent.sock; required when the agent is enabled. A local attos-deck service joins it automatically; remote decks reach it through a consumer-owned SSH account in this group whose key is forced to `attos-deck-agent ssh`.";
      };
      settings = mkOption {
        type = tomlValue;
        default = { };
        description = "agent.toml merged over the shared defaults (systemctl path, restart_failed = true, deny = [sshd.service attos-deck-agent.socket]); units.<name>.allow lists the permitted operations (start, stop, restart, status). Checked at build time.";
      };
    };
  };

  config.assertions = [
    {
      assertion = !cfg.agent.enable || cfg.agent.socketGroup != null;
      message = "modules.attos-deck.agent.socketGroup is required when the agent is enabled.";
    }
  ];
}
