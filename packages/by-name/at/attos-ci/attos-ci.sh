# attos-ci: shared steps for the Forgejo Actions workflows of attos-nix-modules and its consumers.
# Environment: GITHUB_SERVER_URL, GITHUB_REPOSITORY (Actions), FORGEJO_TOKEN (bot).
set -euo pipefail

api() { curl -fsS -H "Authorization: token $FORGEJO_TOKEN" -H 'Content-Type: application/json' "$GITHUB_SERVER_URL/api/v1/repos/$GITHUB_REPOSITORY/$1" "${@:2}"; }

# git with the bot token in a header; the token never appears in URLs or remotes.
auth_git() { git -c "http.extraHeader=Authorization: token $FORGEJO_TOKEN" "$@"; }

# substitute FILE EXPECTED SED_SCRIPT: apply the substitution and fail unless EXPECTED (fixed string) is now in FILE.
substitute() {
  local file=$1 expected=$2
  sed -i -E "$3" "$file"
  grep -qF -- "$expected" "$file" || { echo "::error::$file: substitution did not apply ($expected)" >&2; exit 1; }
}

usage() {
  cat >&2 <<'USAGE'
usage: attos-ci COMMAND [ARGS]
  update-shared            bump attos-nix-modules inputs: HM/hermes pins in flake.nix, flake.lock
  update-packages          nix-update every versioned custom package and registry-based Strata API images, update-nix-fetchgit the Pi and skill sources
  check-consumers REPO...  evaluate consumer hosts (owner/repo:host,host) against this checkout
  pr BRANCH TITLE          commit the work tree to BRANCH and open or update its pull request
USAGE
  exit 2
}

update_shared() {
  local hm tag
  hm=$(git ls-remote https://github.com/nix-community/home-manager refs/heads/master | cut -f1)
  [[ $hm =~ ^[0-9a-f]{40}$ ]] || { echo "::error::could not resolve home-manager master" >&2; exit 1; }
  substitute flake.nix "github:nix-community/home-manager/$hm" "s|(github:nix-community/home-manager/)[0-9a-f]{40}|\1$hm|"
  # Releases only: skip calendar (v2026.x), rc and +canary tags.
  tag=$(git ls-remote --tags --refs https://github.com/NousResearch/hermes-agent 'v*' | sed 's|.*refs/tags/||' | grep -E '^v[0-9]{1,3}\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
  [ -n "$tag" ] || { echo "::error::could not resolve a hermes-agent release tag" >&2; exit 1; }
  substitute flake.nix "github:NousResearch/hermes-agent/$tag" "s|(github:NousResearch/hermes-agent/)v[0-9.]+|\1$tag|"
  substitute README.md "現在は \`$hm\`" "s|(現在は \`)[0-9a-f]{40}|\1$hm|"
  nix flake update
}

# Change summaries for the PR body. update-packages records its own table in
# .attos-ci-summary.md (untracked); flake.lock changes are summarised in pr().
summary_file=.attos-ci-summary.md

lock_summary() {
  git diff --quiet HEAD -- flake.lock 2>/dev/null && return 0
  echo "### flake input"
  echo
  echo "| input | 変更前 | 変更後 |"
  echo "| --- | --- | --- |"
  jq -r --argjson old "$(git show HEAD:flake.lock)" '
    def info: . as $n
      | (($n.original.ref // "") | if . == "" then "" else . + " " end)
      + (($n.locked.rev // $n.locked.narHash // "?") | .[0:7])
      + (if $n.locked.lastModified then " (" + ($n.locked.lastModified | strftime("%Y-%m-%d")) + ")" else "" end);
    .nodes | to_entries[]
    | select(.key != "root" and .value.locked != null)
    | select(($old.nodes[.key].locked // null) != .value.locked)
    | "| \(.key)\(if .value.original.repo then " (" + .value.original.owner + "/" + .value.original.repo + ")" else "" end) | \(if $old.nodes[.key].locked then ($old.nodes[.key] | info) else "（新規）" end) | \(.value | info) |"
  ' flake.lock
  echo
}

package_versions() {
  local pkg
  for pkg in "$@"; do
    printf '%s %s\n' "$pkg" "$(nix eval --raw ".#$pkg.version" 2>/dev/null || echo "?")"
  done
}

# owner/repo of each fetchFromGitHub whose rev changed in the given files.
fetch_summary() {
  git diff -U3 -- "$@" | awk '
    /owner = "/ { split($0, a, "\""); owner = a[2] }
    /repo = "/ { split($0, a, "\""); repo = a[2] }
    /^-.*rev = "/ { split($0, a, "\""); old = a[2] }
    /^\+.*rev = "/ { split($0, a, "\""); printf "| %s/%s | %s | %s |\n", owner, repo, substr(old, 1, 12), substr(a[2], 1, 12) }
  '
}

# Select the newest numeric registry version published for every configured GPU flavor.
# Resolve every digest before writing; missing tags or failed requests leave the file unchanged.
strata_images=modules/strata/nixos.nix
strata_repo=niko1221/strata
strata_image_version() {
  grep -oE "ghcr\.io/$strata_repo:[0-9.]+" "$strata_images" | cut -d: -f2 | sort -Vu | paste -sd,
}

sync_strata_images() {
  local version='' candidate token tag tags registry_tags versions flavor digest work complete
  token=$(curl -fsS "https://ghcr.io/token?scope=repository:$strata_repo:pull" | jq -er '.token | select(type == "string" and length > 0)') || return 1
  registry_tags=$(curl -fsS -H "Authorization: Bearer $token" \
    "https://ghcr.io/v2/$strata_repo/tags/list?n=10000" | jq -er '.tags | select(type == "array" and all(.[]; type == "string")) | .[]') || return 1
  mapfile -t tags < <(grep -oE "ghcr\.io/$strata_repo:[^@\"]+" "$strata_images" | cut -d: -f2)
  [ ${#tags[@]} -gt 0 ] || return 1
  mapfile -t versions < <(printf '%s\n' "$registry_tags" | sed -nE 's/^([0-9]+(\.[0-9]+)*)-.+$/\1/p' | sort -Vu -r)
  for candidate in "${versions[@]}"; do
    complete=true
    for tag in "${tags[@]}"; do
      flavor=${tag#*-}
      if ! grep -qxF -- "$candidate-$flavor" <<<"$registry_tags"; then
        complete=false
        break
      fi
    done
    if "$complete"; then version=$candidate; break; fi
  done
  [ -n "$version" ] || { echo "::warning::no Strata API version has every configured flavor" >&2; return 1; }
  work=$(mktemp) || return 1
  cp "$strata_images" "$work" || { rm -f "$work"; return 1; }
  for tag in "${tags[@]}"; do
    flavor=${tag#*-}
    digest=$(curl -fsSI -H "Authorization: Bearer $token" \
      -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
      "https://ghcr.io/v2/$strata_repo/manifests/$version-$flavor" | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2 }') || { rm -f "$work"; return 1; }
    if ! [[ $digest =~ ^sha256:[0-9a-f]{64}$ ]]; then
      echo "::warning::$strata_repo:$version-$flavor has no valid digest; keeping Strata API images" >&2
      rm -f "$work"
      return 1
    fi
    sed -i -E "s|(ghcr\.io/$strata_repo:)[^@\"]+-$flavor@sha256:[0-9a-f]{64}|\1$version-$flavor@$digest|" "$work"
    grep -qF "$strata_repo:$version-$flavor@$digest" "$work" || { rm -f "$work"; return 1; }
  done
  cat "$work" >"$strata_images"
  rm -f "$work"
}

update_packages() {
  local pkg version failed=() before after packages=(pi context-mode paseo pi-mermaid-studio atcoder-cli atcoder-aclogin mcsmanager pipeasio open-deck-desktop ccpocket-bridge attos-mouse attos-deck)
  local strata_before strata_after
  strata_before=$(strata_image_version)
  before=$(package_versions "${packages[@]}")
  for pkg in "${packages[@]}"; do
    local args=(--flake "$pkg")
    [ "$pkg" = pi ] && args+=(--custom-dep modelData)
    if [ "$pkg" = ccpocket-bridge ]; then
      # The releases feed nix-update reads is flooded by the monorepo's app tags; take the newest bridge tag.
      version=$(git ls-remote --tags --refs https://github.com/K9i-0/ccpocket 'bridge/v*' | sed 's|.*refs/tags/bridge/v||' |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1) || true
      [ -n "$version" ] || { failed+=("$pkg"); continue; }
      args+=(--version "$version")
    fi
    nix-update "${args[@]}" || failed+=("$pkg")
  done
  update-nix-fetchgit modules/pi/resources.nix modules/skills/sources.nix || failed+=(pi-and-skill-sources)
  if ! sync_strata_images; then
    failed+=(strata-images)
  fi
  after=$(package_versions "${packages[@]}")
  strata_after=$(strata_image_version)
  {
    echo "### package"
    echo
    echo "| package | 変更前 | 変更後 |"
    echo "| --- | --- | --- |"
    paste -d" " <(echo "$before") <(echo "$after") | awk '$2 != $4 { printf "| %s | %s | %s |\n", $1, $2, $4 }'
    echo
    echo "### source（fetchFromGitHub）"
    echo
    echo "| repository | 変更前 | 変更後 |"
    echo "| --- | --- | --- |"
    fetch_summary modules/pi/resources.nix modules/skills/sources.nix
    echo
    if ! git diff --quiet -- "$strata_images"; then
      if [ "$strata_before" != "$strata_after" ]; then
        echo "Strata API image: $strata_before → $strata_after（全flavorのtag・digest）"
      else
        echo "Strata API image: $strata_after のdigestを更新（upstreamの再tag）"
      fi
      echo
    fi
    [ ${#failed[@]} -eq 0 ] || echo "更新できなかったもの: ${failed[*]}"
  } >"$summary_file"
  [ ${#failed[@]} -eq 0 ] || echo "::warning::not updated: ${failed[*]}"
}

check_consumers() {
  local spec repo hosts host tmp dir
  nix flake check --no-build "path:$PWD"
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064 # expand $tmp now.
  trap "rm -rf -- '$tmp'" EXIT
  for spec in "$@"; do
    repo=${spec%%:*}; hosts=${spec#*:}
    dir=$tmp/${repo//\//--}
    auth_git clone -q --depth 1 "$GITHUB_SERVER_URL/$repo.git" "$dir"
    for host in ${hosts//,/ }; do
      echo "== $repo#$host"
      nix eval --no-write-lock-file --override-input attos-nix-modules "path:$PWD" --raw "path:$dir#nixosConfigurations.$host.config.system.build.toplevel.drvPath" >/dev/null
    done
  done
}


pr() {
  local branch=$1 title=$2 existing body
  if git diff --quiet && git diff --cached --quiet; then
    echo "no changes"; return 0
  fi
  body=$(
    echo "自動更新のPRです。ビルドはしていません。mergeの前に、必要ならホストで \`nixos-rebuild build\` を実行して確認してください。"
    echo
    lock_summary
    if [ -s "$summary_file" ]; then cat "$summary_file"; fi
  )
  git -c user.name=attos-bot -c user.email=bot@attodao.cc commit -qam "$title"
  auth_git push -qf "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY.git" "HEAD:refs/heads/$branch"
  existing=$(api "pulls?state=open&limit=50" | jq --arg b "$branch" '[.[] | select(.head.ref == $b)][0].number // empty')
  if [ -n "$existing" ]; then
    api "pulls/$existing" -X PATCH -d "$(jq -n --arg t "$title" --arg b "$body" '{title: $t, body: $b}')" >/dev/null
    echo "updated #$existing"
  else
    api pulls -X POST -d "$(jq -n --arg h "$branch" --arg t "$title" --arg b "$body" '{head: $h, base: "main", title: $t, body: $b}')" | jq -r '"opened #\(.number)"'
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
