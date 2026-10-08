{ inputs, pkgs, ... }:

let
  pkgsAtcoder = import inputs.nixpkgs-atcoder {
    system = pkgs.stdenv.system;
  };
  atcoderCli = pkgs.callPackage ./.atcoder/nix/atcoder-cli.nix { };
  aclogin = pkgs.callPackage ./.atcoder/nix/aclogin.nix { };
  snippet = pkgs.callPackage ./.atcoder/nix/snippet.nix { };
  onlineJudgeApiClient = pkgs.python3Packages.online-judge-api-client.overridePythonAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace onlinejudge/service/atcoder.py \
        --replace-fail \
          "^(メモリ制限|Memory Limit): ([0-9.]+) (KB|MB)" \
          "^(メモリ制限|Memory Limit): ([0-9.]+) (KB|MB|MiB)" \
        --replace-fail \
          "elif memory_limit_unit == 'MB':" \
          "elif memory_limit_unit in ('MB', 'MiB'):"
    '';
  });
  onlineJudgeTools = pkgs.python3Packages.online-judge-tools.overridePythonAttrs (old: {
    dependencies = map (
      dependency:
      if (dependency.pname or "") == "online-judge-api-client" then onlineJudgeApiClient else dependency
    ) old.dependencies;
  });
  atcoderConfig = "$DEVENV_ROOT/.devenv/state/config";
  atcoderScript = name: ''
    export XDG_CONFIG_HOME="${atcoderConfig}"
    exec bash "$DEVENV_ROOT/.atcoder/scripts/${name}" "$@"
  '';
in
{
  languages.go = {
    enable = true;
    package = pkgsAtcoder.go_1_25;
    lsp.enable = false;
    delve.enable = false;
  };

  packages = [
    pkgs.coreutils
    pkgs.gopls
    onlineJudgeTools
    atcoderCli
    aclogin
    snippet
  ];

  env.GOTOOLCHAIN = "local";

  enterShell = ''
    config_dir="$(XDG_CONFIG_HOME="${atcoderConfig}" acc config-dir)"
    install -d -m 700 "$config_dir/go"
    cp --remove-destination "$DEVENV_ROOT/.atcoder/template/template.json" "$config_dir/go/template.json"
    cp --remove-destination "$DEVENV_ROOT/.atcoder/template/main.go" "$config_dir/go/main.go"

    external_acc_cookie="$HOME/.config/atcoder-cli-nodejs/session.json"
    project_acc_cookie="$config_dir/session.json"
    if [ -f "$external_acc_cookie" ] && [ ! -e "$project_acc_cookie" ] && [ ! -L "$project_acc_cookie" ]; then
      ln -s "$external_acc_cookie" "$project_acc_cookie"
    fi
  '';

  scripts = {
    "atcoder-go".exec = ''
      exec bash "$DEVENV_ROOT/.atcoder/scripts/project" "$@"
    '';
    acn.exec = atcoderScript "acn";
    act.exec = atcoderScript "act";
    acs.exec = atcoderScript "acs";
    ats.exec = ''
      exec atcoder-snippet "$@"
    '';
    "aclogin-atcoder".exec = ''
      oj_cookie="$HOME/.local/share/online-judge-tools/cookie.jar"
      acc_cookie="$HOME/.config/atcoder-cli-nodejs/session.json"
      install -d -m 700 "$(dirname "$oj_cookie")" "$(dirname "$acc_cookie")"

      if aclogin --tools oj acc \
        --oj-cookie-path "$oj_cookie" \
        --acc-cookie-path "$acc_cookie" "$@"; then
        config_dir="$(XDG_CONFIG_HOME="${atcoderConfig}" acc config-dir)"
        install -d -m 700 "$config_dir"
        ln -sfn "$acc_cookie" "$config_dir/session.json"
      else
        status="$?"
        exit "$status"
      fi
    '';
  };
}
