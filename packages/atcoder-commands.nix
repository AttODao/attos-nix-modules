{
  lib,
  symlinkJoin,
  writeShellApplication,
  coreutils,
  gnugrep,
  go,
  homeDirectory,
  aclogin ? null,
}:
let
  runtimeInputs = [
    coreutils
    gnugrep
    go
  ]
  ++ lib.optional (aclogin != null) aclogin;

  atcoder-go = writeShellApplication {
    name = "atcoder-go";
    inherit runtimeInputs;
    text = ''
      set -eu
      export GOTOOLCHAIN=local
      command="''${1:-init}"
      if [ "$#" -gt 0 ]; then shift; fi

      find_project_root() {
        current="$(pwd -P)"
        while :; do
          if [ -f "$current/go.mod" ]; then
            printf '%s\n' "$current"
            return 0
          fi
          parent="$(dirname "$current")"
          if [ "$parent" = "$current" ]; then
            echo "go.mod was not found; run 'atcoder-go init' at the project root." >&2
            return 1
          fi
          current="$parent"
        done
      }

      ensure_gitignore_entry() {
        gitignore="$1"
        entry="$2"
        if [ ! -e "$gitignore" ]; then
          : > "$gitignore"
        fi
        if ! grep -Fxq "$entry" "$gitignore"; then
          printf '%s\n' "$entry" >> "$gitignore"
        fi
      }

      sync_deps() {
        project_root="''${ATCODER_GO_ROOT:-$(find_project_root)}"
        cd "$project_root"
        # Download the project's recorded dependencies without upgrading modules or its toolchain.
        ${go}/bin/go mod download
      }

      case "$command" in
        init)
          project_root="$(pwd -P)"
          cd "$project_root"
          if [ ! -f go.mod ]; then
            ${go}/bin/go mod init "''${ATCODER_GO_MODULE:-atcoder.jp/golang}"
          fi
          ensure_gitignore_entry "$project_root/.gitignore" ".direnv/"
          ensure_gitignore_entry "$project_root/.gitignore" ".devenv/"
          if [ -f "$project_root/devenv.nix" ] && [ ! -e "$project_root/.envrc" ]; then
            printf '%s\n' "use devenv" > "$project_root/.envrc"
          fi
          echo "initialized AtCoder Go project: $project_root"
          ;;
        sync)
          sync_deps
          ;;
        version)
          ${go}/bin/go version
          ;;
        *)
          echo "usage: atcoder-go [init|sync|version]" >&2
          exit 2
          ;;
      esac
    '';
  };

  atcoder-init = writeShellApplication {
    name = "atcoder-init";
    runtimeInputs = [ atcoder-go ];
    text = ''exec atcoder-go init "$@"'';
  };

  atcoder-sync = writeShellApplication {
    name = "atcoder-sync";
    runtimeInputs = [ atcoder-go ];
    text = ''exec atcoder-go sync "$@"'';
  };

  go-run = writeShellApplication {
    name = "go-run";
    runtimeInputs = [ go ];
    text = ''
      export GOTOOLCHAIN=local
      exec ${go}/bin/go run . "$@"
    '';
  };

  acc-login = writeShellApplication {
    name = "acc-login";
    inherit runtimeInputs;
    text = ''
      set -eu
      if ! command -v aclogin >/dev/null 2>&1; then
        echo "aclogin is required in PATH" >&2
        exit 127
      fi
      # These are literal consumer paths, not shell expressions.
      # shellcheck disable=SC2016
      oj_cookie=${lib.escapeShellArg "${homeDirectory}/.local/share/online-judge-tools/cookie.jar"}
      # shellcheck disable=SC2016
      acc_cookie=${lib.escapeShellArg "${homeDirectory}/.config/atcoder-cli-nodejs/session.json"}
      install -d -m 700 "$(dirname "$oj_cookie")" "$(dirname "$acc_cookie")"
      exec aclogin --tools oj acc \
        --oj-cookie-path "$oj_cookie" \
        --acc-cookie-path "$acc_cookie" \
        "$@"
    '';
  };
in
symlinkJoin {
  name = "atcoder-commands";
  paths = [
    atcoder-go
    atcoder-init
    atcoder-sync
    go-run
    acc-login
  ];
  meta = {
    description = "Small safe AtCoder helper commands";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
  passthru.commands = [
    "atcoder-go"
    "atcoder-init"
    "atcoder-sync"
    "go-run"
    "acc-login"
  ];
}
