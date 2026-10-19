{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.deploy;
in
{
  options.modules.deploy = {
    enable = lib.mkEnableOption "the deploy command that switches this host to the closure CI published";
    source = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "https://[^[:space:]]+[^/]");
      default = null;
      example = "https://git.attodao.cc/AttODao/server-dotfiles";
      description = "Forgejo repository web URL whose deploy branch holds one file per host (store path, then commit); required when enabled.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.source != null;
        message = "modules.deploy.source must name the repository whose CI publishes this host.";
      }
    ];

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "deploy";
        runtimeInputs = [
          pkgs.curl
          pkgs.nvd
        ];
        # Signature checks of the configured substituters decide what may be fetched;
        # nothing is evaluated or built here.
        text = ''
          host=$(hostname)
          record=$(curl -fsS "${cfg.source}/raw/branch/deploy/$host") || {
            echo "deploy: CI has not published $host yet" >&2
            exit 1
          }
          path=$(sed -n 1p <<<"$record")
          commit=$(sed -n 2p <<<"$record")
          case "$path" in
            /nix/store/*-nixos-system-*) ;;
            *) echo "deploy: unexpected record for $host: $path" >&2; exit 1 ;;
          esac
          echo "$host <- ${cfg.source}/commit/$commit"
          if [ "$path" = "$(readlink -f /run/current-system)" ]; then
            echo "already running this build"
            exit 0
          fi
          nix-store --realise "$path" >/dev/null
          nvd diff /run/current-system "$path" || true
          sudo nixos-rebuild switch --no-reexec --store-path "$path"
        '';
      })
    ];
  };
}
