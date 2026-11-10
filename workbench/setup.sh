#!/usr/bin/env bash
# setup.sh [DIR]: create or complete a nix-setup work dir (default: the current directory).
# Clones every repository listed in ./repos side by side, links AGENTS.md to the workbench copy,
# and writes a devenv.yaml that imports this workbench. Existing clones and files are kept.
# Then: cd DIR && devenv shell -- repos-status
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dir=${1:-.}
# Public HTTPS clones; pushes and AGit PRs use ssh://git@git.attodao.cc/AttODao/<repo>.git.
base=${NIX_SETUP_GIT_BASE:-https://git.attodao.cc/AttODao}

mkdir -p "$dir"
cd "$dir"
grep -v -e '^#' -e '^$' "$here/repos" | while read -r repo; do
  if [ -e "$repo/.git" ]; then
    echo "keep $repo"
  else
    git clone -q "$base/$repo.git" "$repo"
    echo "cloned $repo"
  fi
done
[ -d attos-nix-modules/workbench ] || {
  echo "attos-nix-modules/workbench is missing (old checkout?)" >&2
  exit 1
}

ln -sfn attos-nix-modules/workbench/AGENTS.md AGENTS.md
if [ ! -e devenv.yaml ]; then
  cat >devenv.yaml <<'YAML'
# yaml-language-server: $schema=https://devenv.sh/devenv.schema.json
# The work environment itself lives in attos-nix-modules/workbench (scripts, tools, AGENTS.md).
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
imports:
  - ./attos-nix-modules/workbench
YAML
  echo "wrote devenv.yaml"
fi
if [ ! -e devenv.nix ]; then
  # devenv needs a root devenv.nix; local, uncommitted additions for this work dir go here.
  cat >devenv.nix <<'NIX'
# The nix-setup environment is imported from ./attos-nix-modules/workbench (devenv.yaml).
# Only add settings here that are specific to this machine's work dir.
_: { }
NIX
  echo "wrote devenv.nix"
fi
if [ ! -e .gitignore ]; then
  printf '.devenv*\ndevenv.local.nix\ndevenv.local.yaml\n.direnv\n' >.gitignore
fi
echo "done: cd $(pwd) && devenv shell -- repos-status"
