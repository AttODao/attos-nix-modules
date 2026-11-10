# attos-ci: shared steps for the Forgejo Actions workflows of attos-nix-modules and its consumers.
# Environment: GITHUB_SERVER_URL, GITHUB_REPOSITORY (Actions), FORGEJO_TOKEN (bot; not needed by check-consumers).
set -euo pipefail

api() { curl -fsS -H "Authorization: token $FORGEJO_TOKEN" -H 'Content-Type: application/json' "$GITHUB_SERVER_URL/api/v1/repos/$GITHUB_REPOSITORY/$1" "${@:2}"; }

# git with the bot token in a header; the token never appears in URLs or remotes. Without a token
# (pull_request checks, which only read the public consumer repos) it is plain git.
auth_git() {
  if [ -n "${FORGEJO_TOKEN:-}" ]; then
    git -c "http.extraHeader=Authorization: token $FORGEJO_TOKEN" "$@"
  else
    git "$@"
  fi
}

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
  update-packages          nix-update every versioned custom package and registry-based Strata API images, update-nix-fetchgit the Pi and skill sources,
                           then build every package whose derivation changed (a failed build reverts that bump)
  check-flake              evaluate every checks.x86_64-linux drvPath (one nix process each) and the packages output
  check-consumers [--report-warnings] [owner/repo[:host,host]...]
                           check-flake, then evaluate every nixosConfiguration of each consumer (default .forgejo/consumers)
                           against this checkout; fails on evaluation warnings missing from .forgejo/known-warnings
                           (--report-warnings writes them to the PR body instead)
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

# drvPath of each package (version, source hash and every other input), to find what a bump changed.
package_drvs() {
  local pkg
  for pkg in "$@"; do
    printf '%s %s\n' "$pkg" "$(nix eval --raw ".#$pkg.drvPath" 2>/dev/null || echo "?")"
  done
}

# Tracked and untracked paths that differ from HEAD, one per line.
changed_paths() {
  git status --porcelain --untracked-files=all | cut -c4- | sort
}

# Packages whose bump failed to build; read by the workflow after the PR step.
build_failures_file=.attos-ci-build-failures

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
  local strata_before strata_after drvs_before drvs_after old new pre log built=() build_failed=()
  local -A bumped_paths=()
  strata_before=$(strata_image_version)
  before=$(package_versions "${packages[@]}")
  drvs_before=$(package_drvs "${packages[@]}")
  for pkg in "${packages[@]}"; do
    pre=$(changed_paths)
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
    bumped_paths[$pkg]=$(comm -13 <(echo "$pre") <(changed_paths))
  done
  # Evaluation never runs a package's build or installCheck, so a bump with a new upstream layout
  # would first break on a host. Build (x86_64-linux, nothing pushed) every package whose drvPath
  # changed; a failing build restores that package's files and is listed in the PR body.
  drvs_after=$(package_drvs "${packages[@]}")
  rm -f "$build_failures_file"
  while read -r pkg old new; do
    [ "$old" != "$new" ] || continue
    echo "== build $pkg"
    log=$(mktemp)
    if nix build --no-link --max-jobs 1 --print-build-logs ".#$pkg" 2>&1 | tee "$log"; then
      built+=("$pkg")
    else
      build_failed+=("$pkg")
      echo "::error::$pkg: build failed; reverting its bump" >&2
      { echo "- $pkg"; echo; echo '```'; tail -n 30 "$log"; echo '```'; echo; } >>"$build_failures_file"
      while read -r path; do
        [ -n "$path" ] || continue
        if git cat-file -e "HEAD:$path" 2>/dev/null; then git checkout -q HEAD -- "$path"; else rm -f -- "$path"; fi
      done <<<"${bumped_paths[$pkg]:-}"
    fi
    rm -f "$log"
  done < <(paste -d" " <(echo "$drvs_before") <(echo "$drvs_after") | awk '{ print $1, $2, $4 }')
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
    echo "### build（x86_64-linux）"
    echo
    if [ ${#built[@]} -eq 0 ] && [ ${#build_failed[@]} -eq 0 ]; then
      echo "変更したpackageはありません。"
    else
      [ ${#built[@]} -eq 0 ] || echo "buildに成功: ${built[*]}"
      echo
      if [ ${#build_failed[@]} -gt 0 ]; then
        echo "**buildに失敗したため更新を戻したもの: ${build_failed[*]}**（このjobも失敗にします）"
        echo
        cat "$build_failures_file"
      fi
    fi
    echo
    [ ${#failed[@]} -eq 0 ] || echo "更新できなかったもの: ${failed[*]}"
  } >"$summary_file"
  [ ${#failed[@]} -eq 0 ] || echo "::warning::not updated: ${failed[*]}"
  [ ${#build_failed[@]} -eq 0 ] || echo "::error::build failed (bump reverted): ${build_failed[*]}"
}

check_consumers() {
  local report=false all=false spec repo hosts host dir specs
  if [ "${1:-}" = --report-warnings ]; then
    report=true
    shift
  fi
  [ $# -gt 0 ] || all=true
  # Without arguments, evaluate the consumers listed in .forgejo/consumers (owner/repo per line;
  # owner/repo:host,host limits the evaluation to those hosts).
  if [ $# -eq 0 ]; then
    mapfile -t specs < <(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' .forgejo/consumers)
    set -- "${specs[@]}"
  fi
  rm -f "$warnings_report"
  check_flake
  local o=(--no-write-lock-file --override-input attos-nix-modules "path:$PWD")
  for spec in "$@"; do
    repo=${spec%%:*}
    hosts=''
    [ "$spec" = "$repo" ] || hosts=${spec#*:}
    dir=$eval_tmp/${repo//\//--}
    auth_git clone -q --depth 1 "$GITHUB_SERVER_URL/$repo.git" "$dir"
    if [ -z "$hosts" ]; then
      # The host list is the consumer's own nixosConfigurations, so new or retired hosts need no edit here.
      if ! hosts=$(nix eval "${o[@]}" --raw "path:$dir#nixosConfigurations" --apply 'c: builtins.concatStringsSep "," (builtins.attrNames c)'); then
        eval_failed+=("$repo")
        continue
      fi
      echo "== $repo: nixosConfigurations $hosts"
    fi
    for host in ${hosts//,/ }; do
      echo "== $repo#$host"
      evaluate "$repo#$host" nix eval "${o[@]}" --raw "path:$dir#nixosConfigurations.$host.config.system.build.toplevel.drvPath" >/dev/null
    done
  done
  finish_eval "$report" "$all"
}

# --- Evaluation with warning capture ---------------------------------------------------------
# Every evaluation of check-flake / check-consumers goes through evaluate(), which keeps the first
# line of each `evaluation warning:` / `trace: warning:` it prints. finish_eval() compares them with
# $known_warnings (one fixed substring per line, # comments) after everything was evaluated.
known_warnings=.forgejo/known-warnings
warnings_report=.attos-ci-warnings.md
eval_tmp=''
eval_failed=()

eval_setup() {
  [ -z "$eval_tmp" ] || return 0
  eval_tmp=$(mktemp -d)
  # shellcheck disable=SC2064 # expand $eval_tmp now.
  trap "rm -rf -- '$eval_tmp'" EXIT
  : >"$eval_tmp/warnings"
}

# Warning messages on stdin → one normalised message per line (no colours, store hashes or temp dirs).
normalize_warnings() {
  sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' | { grep -E '(evaluation warning|trace: warning):' || true; } |
    sed -E -e 's/^.*(evaluation warning|trace: warning): *//' \
      -e 's|/nix/store/[0-9a-z]{32}-|/nix/store/<hash>-|g' \
      -e "s|$eval_tmp/[^/ ]*|<consumer>|g" \
      -e 's/[[:space:]]+$//'
}

# evaluate CONTEXT CMD...: run CMD with its stderr passed through, and record its warnings as
# "CONTEXT<TAB>message". A failure is recorded and reported by finish_eval, so one run covers every host.
evaluate() {
  local ctx=$1 status=0
  shift
  { "$@" 2>&1 1>&3 | tee "$eval_tmp/stderr" >&2; } 3>&1 || status=$?
  normalize_warnings <"$eval_tmp/stderr" | sort -u | sed "s|^|$ctx\t|" >>"$eval_tmp/warnings"
  if [ "$status" -ne 0 ]; then
    eval_failed+=("$ctx")
    echo "::error::$ctx: evaluation failed" >&2
  fi
}

# Recorded warnings not covered by $known_warnings, as markdown list items with where they appeared.
# With stale=true (every consumer was evaluated), patterns that matched nothing are printed as a
# notice (entries to remove).
unknown_warnings() {
  awk -F'\t' -v known="$known_warnings" -v stale="${1:-false}" '
    BEGIN {
      while ((getline line < known) > 0) {
        sub(/[[:space:]]+$/, "", line)
        if (line !~ /^[[:space:]]*(#|$)/) pat[++n] = line
      }
    }
    {
      hit = 0
      for (i = 1; i <= n; i++) if (index($2, pat[i])) { used[i] = 1; hit = 1; break }
      if (!hit) {
        if (!($2 in where)) { order[++m] = $2; where[$2] = $1 }
        else if (index(", " where[$2] ", ", ", " $1 ", ") == 0) where[$2] = where[$2] ", " $1
      }
    }
    END {
      for (i = 1; i <= m; i++) printf "- `%s`（%s）\n", order[i], where[order[i]]
      if (stale == "true") for (i = 1; i <= n; i++) if (!used[i]) printf "::notice::%s: no evaluation printed \"%s\"\n", known, pat[i] > "/dev/stderr"
    }
  ' "$eval_tmp/warnings"
}

# finish_eval [REPORT [STALE]]: fail on evaluation failures and unknown warnings (REPORT=true writes
# the warnings to $warnings_report for the PR body and does not fail on them).
finish_eval() {
  local report=${1:-false} unknown
  unknown=$(unknown_warnings "${2:-false}")
  if [ -n "$unknown" ]; then
    echo "::error::evaluation warnings not listed in $known_warnings:" >&2
    printf '%s\n' "$unknown" >&2
    if "$report"; then
      {
        echo "### 新しい評価warning"
        echo
        echo "\`$known_warnings\` に無いwarningです。PRのpr-checkはこのままでは失敗します。原因を直すか、出どころをcommentに書いて登録してください。"
        echo
        printf '%s\n' "$unknown"
        echo
      } >"$warnings_report"
    fi
  fi
  if [ ${#eval_failed[@]} -gt 0 ]; then
    echo "::error::evaluation failed: ${eval_failed[*]}" >&2
    return 1
  fi
  [ -z "$unknown" ] || "$report"
}

# Every flake check in its own nix process (many evaluation-only module checks do not fit in the
# runner's memory as one `nix flake check`), then every package drvPath in one process. This covers
# what `nix flake check --no-build` evaluated, so that is not run any more.
check_flake() {
  eval_setup
  local flake="path:$PWD" name names
  # A leading "." makes the attribute path absolute: without it, nix also tries
  # legacyPackages.x86_64-linux.packages..., which is the scope's packages function and fails.
  names=$(nix eval --raw "$flake#.checks.x86_64-linux" --apply 'c: builtins.concatStringsSep " " (builtins.attrNames c)')
  for name in $names; do
    echo "== checks.$name"
    evaluate "checks.$name" nix eval --raw "$flake#.checks.x86_64-linux.\"$name\".drvPath" >/dev/null
  done
  echo "== packages"
  evaluate packages nix eval --json "$flake#.packages.x86_64-linux" --apply 'builtins.mapAttrs (_: p: p.drvPath)' >/dev/null
}


pr() {
  local branch=$1 title=$2 existing body
  if git diff --quiet && git diff --cached --quiet; then
    echo "no changes"; return 0
  fi
  body=$(
    echo "自動更新のPRです。ホストのtoplevelはbuildしていません（\`update/packages\` は変更したcustom packageだけbuildします）。mergeの前に、必要ならホストで \`nixos-rebuild build\` を実行して確認してください。"
    echo
    if [ -s "$warnings_report" ]; then cat "$warnings_report"; fi
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
  check-flake) check_flake && finish_eval ;;
  pr) pr "$@" ;;
  *) usage ;;
esac
