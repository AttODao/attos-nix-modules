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
    marker="$2"
    shift 2
    mkdir -p -- "$marker"
    rm -f -- "$marker/ready" "$marker"/backend-*
    for network in "$@"; do
      ready=false
      for _ in $(seq 1 30); do
        if metadata="$(docker network inspect --format '{{.Driver}} {{.Attachable}} {{.Scope}} {{range $key, $value := .Options}}{{$key}} {{end}}' "$network" 2>/dev/null)"; then
          # Never silently reuse an unencrypted overlay or recreate an existing network.
          if [[ "$metadata" != "overlay true swarm "* || " $metadata " != *" encrypted "* ]]; then
            echo "Existing $network must be an encrypted attachable overlay; migrate it explicitly" >&2
            exit 1
          fi
          ready=true
        elif docker network create --driver overlay --attachable --opt encrypted "$network"; then
          ready=true
        fi
        if [ "$ready" = true ]; then
          touch -- "$marker/$network"
          break
        fi
        sleep 1
      done
      if [ "$ready" != true ]; then
        echo "Failed to ensure the $network overlay network" >&2
        exit 1
      fi
    done
    touch -- "$marker/ready"
    ;;
  fetch)
    url="$2"
    source_address="$3"
    token_file="$4"
    umask 077
    mkdir -p -- "$(dirname -- "$token_file")"
    token_tmp="$(mktemp "${token_file}.XXXXXX")"
    trap 'rm -f -- "$token_tmp"' EXIT
    source_args=()
    if [ -n "$source_address" ]; then source_args=(--interface "$source_address"); fi
    for _ in $(seq 1 60); do
      if curl --noproxy '*' "${source_args[@]}" -fsS --max-time 2 "$url" > "$token_tmp" 2>/dev/null; then
        case "$(tr -d '\r\n' < "$token_tmp")" in
          SWMTKN-1-*)
            chmod 0600 "$token_tmp"
            mv -f -- "$token_tmp" "$token_file"
            exit 0
            ;;
        esac
      fi
      sleep 2
    done
    echo "Failed to fetch the Swarm worker token" >&2
    exit 1
    ;;
  wait)
    url="$2"
    for _ in $(seq 1 60); do
      if curl --noproxy '*' -fsS --max-time 2 "$url" >/dev/null; then
        if [ -n "${3:-}" ] && metadata="$(docker network inspect --format '{{.Driver}} {{.Attachable}} {{.Scope}} {{range $key, $value := .Options}}{{$key}} {{end}}' "$3" 2>/dev/null)"; then
          if [[ "$metadata" != "overlay true swarm "* || " $metadata " != *" encrypted "* ]]; then
            echo "Local $3 is not an encrypted attachable Swarm overlay" >&2
            exit 1
          fi
        fi
        # Docker materializes remote attachable overlays on the first container
        # attachment; requiring local presence here would deadlock fresh workers.
        exit 0
      fi
      sleep 2
    done
    echo "Failed to confirm the service overlay network" >&2
    exit 1
    ;;
  *)
    echo "Usage: swarm.sh manager|worker|network|fetch|wait ..." >&2
    exit 2
    ;;
esac
