#!/bin/bash
# herdr-entrypoint.sh — the herdr container is the only writer of
# herdr_socket (rw). Responsibilities before exec'ing `herdr server`:
#   1. Unlink stale sockets left over from an unclean stop (a fresh bind()
#      would otherwise fail EADDRINUSE) — only if the path is actually a
#      leftover Unix socket, not just any file.
#   2. Verify state directories are writable by the running user, and fail
#      loudly (not silently) with the observed owner/mode if not — this is
#      the belt-and-suspenders check for Blocking Fix #2 (PUID immutability):
#      changing PUID/PGID after volumes already have data requires a manual
#      migration; see README.md "Changing PUID/PGID after first run".
set -euo pipefail

SOCKET_DIR="/run/herdr"
API_SOCKET="${SOCKET_DIR}/herdr.sock"
CLIENT_SOCKET="${SOCKET_DIR}/herdr-client.sock"

fail_not_writable() {
  local path="$1"
  echo "herdr-entrypoint: FATAL — '${path}' is not writable by uid=$(id -u) gid=$(id -g)" >&2
  echo "herdr-entrypoint: observed: $(stat -c '%U(%u):%G(%g) mode=%a' "$path" 2>&1 || echo 'stat failed')" >&2
  echo "herdr-entrypoint: this usually means PUID/PGID changed since this volume was first created." >&2
  echo "herdr-entrypoint: see README.md, section 'Changing PUID/PGID after first run', for the migration procedure." >&2
  exit 1
}

check_writable() {
  local dir="$1"
  mkdir -p "$dir" 2>/dev/null || true
  if [ ! -w "$dir" ]; then
    fail_not_writable "$dir"
  fi
}

check_writable "$SOCKET_DIR"
check_writable "$HOME/.config/herdr"
check_writable "$HOME/.pi/agent"
check_writable /workspace

for sock in "$API_SOCKET" "$CLIENT_SOCKET"; do
  if [ -e "$sock" ] && [ -S "$sock" ]; then
    echo "herdr-entrypoint: unlinking stale socket $sock"
    rm -f "$sock"
  elif [ -e "$sock" ]; then
    echo "herdr-entrypoint: WARNING — $sock exists and is not a socket; leaving it alone" >&2
  fi
done

if [ "$#" -gt 0 ]; then
  echo "herdr-entrypoint: exec'ing explicit command (uid=$(id -u) gid=$(id -g)): $*"
  exec "$@"
fi

echo "herdr-entrypoint: starting herdr server (uid=$(id -u) gid=$(id -g))"
exec herdr server
