# attos-ci: shared steps for the Forgejo Actions workflows of attos-nix-modules and its consumers.
# Environment: GITHUB_SERVER_URL, GITHUB_REPOSITORY (Actions), FORGEJO_TOKEN (bot).
set -euo pipefail

api() { curl -fsS -H "Authorization: token $FORGEJO_TOKEN" -H 'Content-Type: application/json' "$GITHUB_SERVER_URL/api/v1/repos/$GITHUB_REPOSITORY/$1" "${@:2}"; }

usage() {
  cat >&2 <<'USAGE'
usage: attos-ci COMMAND [ARGS]
  update-shared            bump attos-nix-modules inputs: HM/hermes pins in flake.nix, flake.lock
  update-packages          nix-update every versioned custom package, update-nix-fetchgit the Pi and skill sources
  check-consumers REPO...  evaluate consumer hosts (owner/repo:host,host) against this checkout
  pr BRANCH TITLE          commit the work tree to BRANCH and open or update its pull request
USAGE
  exit 2
}

update_shared() {
  local hm tag
  hm=$(git ls-remote https://github.com/nix-community/home-manager refs/heads/master | cut -f1)
  sed -i -E "s|(github:nix-community/home-manager/)[0-9a-f]{40}|\1$hm|" flake.nix
  # Releases only: skip calendar (v2026.x), rc and +canary tags.
  tag=$(git ls-remote --tags --refs https://github.com/NousResearch/hermes-agent 'v*' | sed 's|.*refs/tags/||' | grep -E '^v[0-9]{1,3}\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
  sed -i -E "s|(github:NousResearch/hermes-agent/)v[0-9.]+|\1$tag|" flake.nix
  sed -i -E "s|^(  version = \")[0-9.]+(\";)|\1${tag#v}\2|" packages/by-name/he/hermes-desktop/package.nix
  sed -i -E "s|(Home Manager revision: \`?)[0-9a-f]{40}|\1$hm|; s|(現在は \`)[0-9a-f]{40}|\1$hm|" README.md
  nix flake update
}

update_packages() {
  local pkg failed=()
  for pkg in pi context-mode paseo pi-mermaid-studio atcoder-cli atcoder-aclogin mcsmanager pipeasio; do
    local args=(--flake "$pkg")
    [ "$pkg" = pi ] && args+=(--custom-dep modelData)
    nix-update "${args[@]}" || failed+=("$pkg")
  done
  update-nix-fetchgit modules/pi/resources.nix modules/skills/sources.nix || failed+=(pi-and-skill-sources)
  [ ${#failed[@]} -eq 0 ] || echo "::warning::not updated: ${failed[*]}"
}

check_consumers() {
  local spec repo hosts host dir
  nix flake check --no-build "path:$PWD"
  for spec in "$@"; do
    repo=${spec%%:*}; hosts=${spec#*:}
    dir=$(mktemp -d)
    git clone -q --depth 1 "https://bot:$FORGEJO_TOKEN@${GITHUB_SERVER_URL#https://}/$repo.git" "$dir"
    for host in ${hosts//,/ }; do
      echo "== $repo#$host"
      nix eval --no-write-lock-file --override-input attos-nix-modules "path:$PWD" --raw "path:$dir#nixosConfigurations.$host.config.system.build.toplevel.drvPath" >/dev/null
    done
  done
}


pr() {
  local branch=$1 title=$2 existing
  if git diff --quiet && git diff --cached --quiet; then
    echo "no changes"; return 0
  fi
  git -c user.name=attos-bot -c user.email=bot@attodao.cc commit -qam "$title"
  git push -qf "https://bot:$FORGEJO_TOKEN@${GITHUB_SERVER_URL#https://}/$GITHUB_REPOSITORY.git" "HEAD:refs/heads/$branch"
  existing=$(api "pulls?state=open&limit=50" | jq --arg b "$branch" '[.[] | select(.head.ref == $b)][0].number // empty')
  if [ -n "$existing" ]; then
    echo "updated #$existing"
  else
    api pulls -X POST -d "$(jq -n --arg h "$branch" --arg t "$title" '{head: $h, base: "main", title: $t, body: "自動更新のPRです。ビルドはしていません。mergeの前に、必要ならホストで `nixos-rebuild build` を実行して確認してください。"}')" | jq -r '"opened #\(.number)"'
  fi
}


[ $# -gt 0 ] || usage
command=$1
shift
case "$command" in
  update-shared) update_shared ;;
  update-packages) update_packages ;;
  check-consumers) check_consumers "$@" ;;
  pr) pr "$@" ;;
  *) usage ;;
esac
