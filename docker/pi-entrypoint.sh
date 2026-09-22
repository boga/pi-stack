#!/bin/bash
# pi-entrypoint.sh — standalone `pi` container. No daemon mode exists for pi
# (there is no `pi server`; -p/--print is non-interactive-and-exit), so the
# real command is `sleep infinity` and humans run
# `docker compose exec -it pi pi`. This entrypoint just validates the
# environment before handing off.
set -euo pipefail

source /usr/local/lib/herdr-docker/wait-for-herdr-socket.sh

if [ -n "${HERDR_SSH_HOST:-}" ]; then
  echo "pi-entrypoint: FATAL — HERDR_SSH_HOST is set ('${HERDR_SSH_HOST}')." >&2
  echo "pi-entrypoint: this stack uses a shared Unix-socket volume, not SSH. Unset HERDR_SSH_HOST." >&2
  exit 1
fi

fail_not_writable() {
  local path="$1"
  echo "pi-entrypoint: FATAL — '${path}' is not writable by uid=$(id -u) gid=$(id -g)" >&2
  echo "pi-entrypoint: observed: $(stat -c '%U(%u):%G(%g) mode=%a' "$path" 2>&1 || echo 'stat failed')" >&2
  echo "pi-entrypoint: this usually means PUID/PGID changed since this volume/bind-mount was first created." >&2
  echo "pi-entrypoint: see README.md, section 'Changing PUID/PGID after first run', for the migration procedure." >&2
  exit 1
}

check_writable() {
  local dir="$1"
  mkdir -p "$dir" 2>/dev/null || true
  if [ ! -w "$dir" ]; then
    fail_not_writable "$dir"
  fi
}

check_writable "$HOME/.pi/agent"
check_writable /workspace

if ! wait_for_herdr_sockets "/run/herdr/herdr.sock"; then
  exit 1
fi

# -----------------------------------------------------------------------
# INERT — deferred this pass (explicitly out of scope):
#
#   GitHub token / kubeconfig credential wiring would go here, e.g.:
#     - copy a mounted `secrets/gh-token` into `$HOME/.config/gh/hosts.yml`
#       (or run `gh auth login --with-token < secrets/gh-token`)
#     - copy a mounted `secrets/kubeconfig` into `$HOME/.kube/config`
#     - corresponding `secrets:` block in compose.yaml and RBAC docs in
#       README.md
#
#   gh and kubectl BINARIES are already installed in this image; only the
#   credential-injection plumbing is deferred. See secrets/.gitkeep.
# -----------------------------------------------------------------------

echo "pi-entrypoint: ready (uid=$(id -u) gid=$(id -g)). Run: docker compose exec -it pi pi"
exec "$@"
