{
  lib,
  pkgs,
  ...
}:

# attos-nix-modules / server-nix / personal-nix を扱う作業環境（nix-setup）。
# 3リポジトリは作業dir（DEVENV_ROOT）直下に置き、作業はそれぞれのworktree（.worktrees/<repo>-<topic>）で行う。
# 作業dirの devenv.yaml が `imports: [ ./attos-nix-modules/workbench ]` でこのファイルを読む（作り方は ./setup.sh）。
let
  # 対象repoの一覧は ./repos（setup.shと共有）。
  repos = lib.concatStringsSep " " (
    lib.filter (l: l != "" && !lib.hasPrefix "#" l) (lib.splitString "\n" (builtins.readFile ./repos))
  );
  # wt_state <repo dir> <worktree>: worktreeの状態を1語で返す（最後のfetch時点のorigin/mainと比べる）。
  #   dirty:N   未コミットの変更がN件
  #   ahead:N   origin/mainにないcommitがN件（作業中・review待ち）
  #   new       作ってからcommitしていない（作業を始めたばかりの可能性がある）
  #   merged    変更もcommitもなく、branchの全commitがorigin/mainに入っている
  #   detached / unknown  branchがない・作成元が分からない（触らない）
  wtState = ''
    wt_state() {
      b=$(git -C "$2" branch --show-current)
      [ -n "$b" ] || { echo detached; return; }
      n=$(git -C "$2" status --porcelain | wc -l)
      [ "$n" -eq 0 ] || { echo "dirty:$n"; return; }
      n=$(git -C "$2" rev-list --count origin/main..HEAD)
      [ "$n" -eq 0 ] || { echo "ahead:$n"; return; }
      created=$(git -C "$1" reflog show --format=%H "refs/heads/$b" 2>/dev/null | tail -1)
      [ -n "$created" ] || { echo unknown; return; }
      if [ "$created" = "$(git -C "$2" rev-parse HEAD)" ]; then echo new; else echo merged; fi
    }
  '';
  # TOPIC が設定され、そのworktreeがあればworktreeを、なければ元のcheckoutを返す。
  repoDir = ''
    repo_dir() {
      if [ -n "''${TOPIC:-}" ] && [ -d "$DEVENV_ROOT/.worktrees/$1-$TOPIC" ]; then
        echo "$DEVENV_ROOT/.worktrees/$1-$TOPIC"
      else
        echo "$DEVENV_ROOT/$1"
      fi
    }
  '';
  # 重い評価はattodesk（i7-12700・78GiB）で行う。attofort（12GiB）はhermes containerとrunner VMでメモリが足りず、
  # このcontainerでの評価はhostのOOMを起こす。届かないとき（attodesk停止・WireGuard未接続）と EVAL_HOST=local のときは
  # このcontainerで評価する。eval hostには.gitを除いたrepoを ~/.cache/nix-setup-remote/<TOPIC|main>/<repo> へ写す。
  evalHost = ''
    # 引数を1つのshell文字列へquoteする。引数0個で空文字の引数を作らない（nixが`unexpected argument`で止まる）。
    quote_args() {
      [ $# -eq 0 ] || printf '%q ' "$@"
    }
    eval_host() {
      h=''${EVAL_HOST:-attodesk.attodao.cc}
      if [ "$h" != local ] && ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" true 2>/dev/null; then
        echo "$h"
      else
        echo local
      fi
    }
    # sync_repo <host> <src dir> <repo名>: 写した先の絶対pathを返す。
    sync_repo() {
      dst=".cache/nix-setup-remote/''${TOPIC:-main}/$3"
      tar -C "$2" --exclude=.git -cf - . | ssh "$1" "rm -rf ~/$dst && mkdir -p ~/$dst && tar -C ~/$dst -xf - && echo \$HOME/$dst"
    }
    # run_on <repo名> <command>: repo（TOPICでworktree）とattos-nix-modulesを用意し、repoのdirで
    # MODULES=<attos-nix-modulesのdir> を付けて bash -c <command> を実行する。
    run_on() {
      d=$(repo_dir "$1")
      m=$(repo_dir attos-nix-modules)
      h=$(eval_host)
      if [ "$h" = local ]; then
        echo "== $1: local $d (attos-nix-modules: $m)" >&2
        (cd "$d" && MODULES="$m" bash -c "$2")
      else
        rm_=$(sync_repo "$h" "$m" attos-nix-modules) || return 1
        if [ "$1" = attos-nix-modules ]; then rd=$rm_; else rd=$(sync_repo "$h" "$d" "$1") || return 1; fi
        echo "== $1: $h:$rd (from $d; attos-nix-modules: $m)" >&2
        ssh "$h" "cd $rd && MODULES=$rm_ bash -c $(printf %q "$2")"
      fi
    }
  '';
  # flake checkの--no-buildはIFD（評価中にpackageの中身を読むもの。hermes-agentのmodule等）をbuildしないので、
  # eval hostのstoreに無いと`path '...' is not valid`で落ちる。そのときはtoplevelのdrvPathを評価してIFDをstoreへ入れ、1回だけやり直す。
  checkConsumer = repo: ''
    ${repoDir}
    ${evalHost}
    o="--no-write-lock-file --override-input attos-nix-modules path:\$MODULES"
    c="nix flake check --no-build $o path:. $(quote_args "$@")"
    run_on ${repo} "$c || { echo '== IFDをstoreへ入れて再評価' >&2; nix eval $o --json path:.#nixosConfigurations --apply 'builtins.mapAttrs (_: h: h.config.system.build.toplevel.drvPath)' >/dev/null && $c; }"
  '';
in
{
  packages = with pkgs; [
    git
    jq

    # Nix の整形・lint・LSP（各flakeの formatter は nixfmt）
    nixfmt
    nixd
    nil
    statix
    deadnix

    # 評価・差分確認
    nix-output-monitor
    nix-tree
    nvd

    # secrets（sops-nix）
    sops
    age
    ssh-to-age
  ];

  # 共有モジュールを利用側flakeへ未pushのまま差し込んで評価する。
  # 未追跡ファイルを含めるため path: flake を使う（各repoのAGENTS.mdの方針）。
  # TOPIC=<topic> を付けると、.worktrees/<repo>-<topic> があるrepoはworktreeを評価する。
  scripts = {
    check-modules = {
      description = "attos-nix-modules を nix flake check --no-build で評価（attodeskが届けばattodeskで評価（EVAL_HOST=localで手元）、TOPIC=<topic>でworktree）";
      exec = ''
        ${repoDir}
        ${evalHost}
        run_on attos-nix-modules "nix flake check --no-build --no-write-lock-file path:. $(quote_args "$@")"
      '';
    };
    check-server = {
      description = "server-nix を作業中の attos-nix-modules で評価（attodeskが届けばattodeskで評価（EVAL_HOST=localで手元）、TOPIC=<topic>でworktree）";
      exec = checkConsumer "server-nix";
    };
    check-personal = {
      description = "personal-nix を作業中の attos-nix-modules で評価（attodeskが届けばattodeskで評価（EVAL_HOST=localで手元）、TOPIC=<topic>でworktree）";
      exec = checkConsumer "personal-nix";
    };
    check-all = {
      description = "3リポジトリをすべて評価（attodeskが届けばattodeskで評価（EVAL_HOST=localで手元）、TOPIC=<topic>でworktree）";
      exec = ''
        set -e
        check-modules "$@"
        check-server "$@"
        check-personal "$@"
      '';
    };
    on-eval-host = {
      description = "on-eval-host <repo> '<command>': attodesk（届かなければ手元）でrepoのdirに入り、MODULES=<attos-nix-modules>付きで実行（TOPIC=<topic>でworktree）";
      exec = ''
        ${repoDir}
        ${evalHost}
        run_on "''${1:?usage: on-eval-host <repo> '<command>'}" "''${2:?usage: on-eval-host <repo> '<command>'}"
      '';
    };
    sync-repos = {
      description = "3リポジトリをfetchし、mainにいて変更のないcheckoutだけorigin/mainへfast-forwardする（ブランチは切り替えない）";
      exec = ''
        rc=0
        for r in ${repos}; do
          d="$DEVENV_ROOT/$r"
          echo "== $r"
          if ! git -C "$d" fetch --prune origin; then
            echo "fetchに失敗"; rc=1; continue
          fi
          b=$(git -C "$d" branch --show-current)
          if [ "$b" != main ]; then
            echo "元のcheckoutが main ではない（$b）。他の作業中とみなし触らない"; continue
          fi
          if [ -n "$(git -C "$d" status --porcelain)" ]; then
            echo "未コミットの変更があるため触らない:"; git -C "$d" status --short; continue
          fi
          if ! git -C "$d" merge -q --ff-only origin/main; then
            echo "main を origin/main へ fast-forward できない"; rc=1; continue
          fi
          git -C "$d" log --oneline -1
        done
        exit $rc
      '';
    };
    wt-add = {
      description = "wt-add <branch> [repo...]: origin/main から .worktrees/<repo>-<branchの末尾> を作る（既定は3リポジトリ）";
      exec = ''
        set -e
        branch=''${1:?usage: wt-add <branch> [repo...]}; shift
        topic=''${branch##*/}
        [ $# -gt 0 ] || set -- ${repos}
        for r in "$@"; do
          w="$DEVENV_ROOT/.worktrees/$r-$topic"
          echo "== $r: $w ($branch)"
          git -C "$DEVENV_ROOT/$r" fetch --prune origin
          git -C "$DEVENV_ROOT/$r" worktree add --no-track -b "$branch" "$w" origin/main
        done
        echo "評価: TOPIC=$topic check-all"
      '';
    };
    wt-remove = {
      description = "wt-remove <topic> [repo...]: 自分のworktreeを外す（未コミットの変更があれば拒否）。ブランチは残す";
      exec = ''
        topic=''${1:?usage: wt-remove <topic> [repo...]}; shift
        [ $# -gt 0 ] || set -- ${repos}
        for r in "$@"; do
          w="$DEVENV_ROOT/.worktrees/$r-$topic"
          [ -d "$w" ] || continue
          echo "== $r: $w"
          git -C "$DEVENV_ROOT/$r" worktree remove "$w"
        done
      '';
    };
    wt-prune = {
      description = "wt-prune [-n] [repo...]: fetchしてから、変更・未merge commitがなくbranchがorigin/mainに入ったworktree（repos-statusのmerged）を外す。-nは表示だけ。ブランチは残す";
      exec = ''
        ${wtState}
        dry=
        if [ "''${1:-}" = -n ]; then dry=1; shift; fi
        [ $# -gt 0 ] || set -- ${repos}
        for r in "$@"; do
          d="$DEVENV_ROOT/$r"
          echo "== $r"
          git -C "$d" fetch -q --prune origin || { echo "fetchに失敗"; continue; }
          git -C "$d" worktree list --porcelain | sed -n 's/^worktree //p' | while read -r w; do
            case "$w" in "$DEVENV_ROOT/.worktrees/"*) ;; *) continue ;; esac
            s=$(wt_state "$d" "$w")
            if [ "$s" = merged ]; then
              if [ -n "$dry" ]; then echo "would remove $w"; else git -C "$d" worktree remove "$w" && echo "removed $w"; fi
            else
              echo "keep $w ($s)"
            fi
          done
        done
      '';
    };
    repos-status = {
      description = "3リポジトリの元のcheckoutと各worktreeのbranch・状態（dirty:N / ahead:N / new / merged）を表示（最後のfetch時点）";
      exec = ''
        ${wtState}
        for r in ${repos}; do
          d="$DEVENV_ROOT/$r"
          echo "== $r"
          git -C "$d" status -sb | head -1
          git -C "$d" worktree list --porcelain | sed -n 's/^worktree //p' | while read -r w; do
            [ "$w" != "$d" ] || continue
            printf '  %-9s %s [%s]\n' "$(wt_state "$d" "$w")" "''${w#"$DEVENV_ROOT"/}" "$(git -C "$w" branch --show-current)"
          done
        done
      '';
    };
  };

  enterShell = ''
    echo "nix-setup: wt-add / wt-remove / wt-prune / sync-repos / check-modules / check-server / check-personal / check-all / on-eval-host / repos-status"
  '';

  enterTest = ''
    nix --version
    nixfmt --version
    sops --version
    for r in ${repos}; do
      test -f "$DEVENV_ROOT/$r/flake.nix"
    done
  '';
}
