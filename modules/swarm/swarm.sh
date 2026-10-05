#!/usr/bin/env bash
# Shared Swarm operations; all addresses and secret paths are supplied at runtime.
set -euo pipefail

case "$1" in
  manager)
    address="$2"
    token_file="$3"
    state="$(docker info --format '{{.Swarm.LocalNodeState}}')"
    if [ "$state" != active ]; then
      # Docker prints the join token after init; never send it to the journal.
      docker swarm init --advertise-addr "$address" --data-path-addr "$address" >/dev/null
    fi
    if [ "$(docker info --format '{{.Swarm.ControlAvailable}}')" != true ]; then
      echo "Existing Swarm node is not a manager; refusing to change its role" >&2
      exit 1
    fi
    umask 077
    mkdir -p -- "$(dirname -- "$token_file")"
    token_tmp="$(mktemp "${token_file}.XXXXXX")"
    trap 'rm -f -- "$token_tmp"' EXIT
    docker swarm join-token -q worker > "$token_tmp"
    test -s "$token_tmp"
    chmod 0600 "$token_tmp"
    mv -f -- "$token_tmp" "$token_file"
    ;;
  worker)
    manager="$2"
    token_file="$3"
    state="$(docker info --format '{{.Swarm.LocalNodeState}}')"
    if [ "$state" = active ]; then
      if [ "$(docker info --format '{{.Swarm.ControlAvailable}}')" != false ]; then
        echo "Existing Swarm node is not a worker; refusing to change its role" >&2
        exit 1
      fi
      exit 0
    fi
    token="$(< "$token_file")"
    test -n "$token"
    docker swarm join --token "$token" "$manager"
    ;;
  network)
    subnet="$2"
    gateway="$3"
    marker="$4"
    for _ in $(seq 1 30); do
      if docker network inspect traefik >/dev/null 2>&1 || docker network create --driver overlay --attachable --subnet "$subnet" --gateway "$gateway" traefik; then
        mkdir -p -- "$(dirname -- "$marker")"
        touch -- "$marker"
        exit 0
      fi
      sleep 1
    done
    echo "Failed to ensure the traefik overlay network" >&2
    exit 1
    ;;
  wait)
    url="$2"
    for _ in $(seq 1 60); do
      if curl -fsS --max-time 2 "$url" >/dev/null; then exit 0; fi
      sleep 2
    done
    echo "Failed to confirm the traefik overlay network" >&2
    exit 1
    ;;
  *)
    echo "Usage: swarm.sh manager|worker|network|wait ..." >&2
    exit 2
    ;;
esac
