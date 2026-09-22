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

# _positive_int_or_die <name> <value> — validate that <value> is a
# positive integer (no sign, no decimals, no whitespace, no garbage). On
# failure, print a clear error and exit 1 immediately rather than letting
# an unbounded/garbage value make the caller's wait loop silently
# infinite (e.g. `[ "$waited" -ge "$timeout_s" ]` with a non-numeric
# $timeout_s throws "integer expression expected" every iteration and
# never trips the timeout branch).
_positive_int_or_die() {
  local name="$1"
  local value="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "wait-for-herdr-socket: FATAL - ${name}='${value}' is not a positive integer" >&2
      exit 1
      ;;
  esac
  if [ "$value" -eq 0 ]; then
    echo "wait-for-herdr-socket: FATAL - ${name}='${value}' must be a positive integer (> 0)" >&2
    exit 1
  fi
}

wait_for_herdr_sockets() {
  local timeout_default=60
  local poll_default=1

  _positive_int_or_die "HERDR_WAIT_TIMEOUT default" "$timeout_default"
  _positive_int_or_die "HERDR_WAIT_POLL_INTERVAL default" "$poll_default"

  local timeout_s="${HERDR_WAIT_TIMEOUT:-$timeout_default}"
  local poll_s="${HERDR_WAIT_POLL_INTERVAL:-$poll_default}"
  _positive_int_or_die "HERDR_WAIT_TIMEOUT" "$timeout_s"
  _positive_int_or_die "HERDR_WAIT_POLL_INTERVAL" "$poll_s"

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
    sleep "$poll_s"
    waited=$((waited + poll_s))
  done
}
