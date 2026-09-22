#!/bin/bash
# wait-for-herdr-socket.sh — sourced by pi-entrypoint.sh and
# roamgate-entrypoint.sh. Provides wait_for_herdr_sockets(), a bounded
# retry loop that polls for one or more Unix socket paths to appear as
# actual sockets (test -S, not just any file) before the caller execs its
# real command.
#
# On timeout: print `ls -la` of the socket directory, suggest checking
# `docker compose logs herdr`, and suggest confirming PUID/GID match across
# services, then return non-zero (caller should exit 1).

wait_for_herdr_sockets() {
  local timeout_s="${HERDR_WAIT_TIMEOUT:-60}"
  local socket_dir="/run/herdr"
  local -a sockets=("$@")
  local waited=0

  echo "wait-for-herdr-socket: waiting up to ${timeout_s}s for: ${sockets[*]}"

  while :; do
    local all_ready=1
    for sock in "${sockets[@]}"; do
      if [ ! -S "$sock" ]; then
        all_ready=0
        break
      fi
    done
    if [ "$all_ready" -eq 1 ]; then
      echo "wait-for-herdr-socket: all sockets present after ${waited}s"
      return 0
    fi
    if [ "$waited" -ge "$timeout_s" ]; then
      echo "wait-for-herdr-socket: TIMEOUT after ${timeout_s}s waiting for: ${sockets[*]}" >&2
      echo "wait-for-herdr-socket: contents of ${socket_dir}:" >&2
      ls -la "$socket_dir" 2>&1 >&2 || true
      echo "wait-for-herdr-socket: check 'docker compose logs herdr' for startup errors." >&2
      echo "wait-for-herdr-socket: confirm PUID/GID are identical across all three services (herdr writes rw, this container reads ro)." >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}
