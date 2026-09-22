#!/bin/bash
# roamgate-entrypoint.sh — validates sockets/config-dir/writability, then
# execs roamgate. roamgate needs BOTH HERDR_SOCKET_PATH (control) and
# HERDR_CLIENT_SOCKET_PATH (binary terminal-stream) or it renders a UI that
# lists panes but shows no terminal output.
set -euo pipefail

source /usr/local/lib/herdr-docker/wait-for-herdr-socket.sh

if [ -n "${HERDR_SSH_HOST:-}" ]; then
  echo "roamgate-entrypoint: FATAL — HERDR_SSH_HOST is set ('${HERDR_SSH_HOST}')." >&2
  echo "roamgate-entrypoint: this stack uses a shared Unix-socket volume, not SSH. Unset HERDR_SSH_HOST." >&2
  exit 1
fi

fail_not_writable() {
  local path="$1"
  echo "roamgate-entrypoint: FATAL — '${path}' is not writable by uid=$(id -u) gid=$(id -g)" >&2
  echo "roamgate-entrypoint: observed: $(stat -c '%U(%u):%G(%g) mode=%a' "$path" 2>&1 || echo 'stat failed')" >&2
  echo "roamgate-entrypoint: this usually means PUID/PGID changed since this volume/bind-mount was first created." >&2
  echo "roamgate-entrypoint: see README.md, section 'Changing PUID/PGID after first run', for the migration procedure." >&2
  exit 1
}

check_writable() {
  local dir="$1"
  mkdir -p "$dir" 2>/dev/null || true
  if [ ! -w "$dir" ]; then
    fail_not_writable "$dir"
  fi
}

check_writable "$HOME/.config/herdr"
check_writable /workspace

# roamgate's own assertSafeDataPath() rejects a symlinked config parent —
# check it here too, so the failure is attributable to this entrypoint
# rather than a cryptic roamgate stack trace.
config_dir="$HOME/.config/herdr"
if [ -L "$config_dir" ]; then
  echo "roamgate-entrypoint: FATAL — '${config_dir}' is a symlink; roamgate requires a real directory." >&2
  exit 1
fi

if ! wait_for_herdr_sockets "/run/herdr/herdr.sock" "/run/herdr/herdr-client.sock"; then
  exit 1
fi

echo "roamgate-entrypoint: Herdr sockets configured (control + client), Herdr reachable at ${HERDR_SOCKET_PATH:-unset}"
echo "roamgate-entrypoint: starting roamgate (uid=$(id -u) gid=$(id -g)) on ${HOST:-0.0.0.0}:${PORT:-8787}"
exec "$@"
