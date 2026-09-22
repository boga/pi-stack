#!/bin/bash
# create-user.sh — build-time UID/GID-safe user+group provisioning.
#
# Usage: create-user.sh <username> <groupname> <uid> <gid> <home>
#
# Handles the case where the base image already has an account/group at the
# requested numeric id (e.g. node:22-bookworm-slim ships "node" at 1000:1000,
# which is also this stack's default PUID/PGID). Strategy:
#   - UID collision with a DIFFERENT username: repurpose that account via
#     `usermod -l <target> -d <home> -m -s /bin/bash <existing>` (reuses the
#     UID cleanly instead of failing on useradd -u).
#   - GID collision with a DIFFERENT groupname: reuse the existing group by
#     renaming it via `groupmod -n <target> <existing>` rather than failing
#     on groupadd -g.
#   - PUID=0 or PGID=0: hard error, refuse to run as root.
#   - After creation, assert `id <username>` succeeds and home dir ownership
#     is correct — a build-time verification, not an assumption.
set -euo pipefail

usage() {
  echo "usage: $0 <username> <groupname> <uid> <gid> <home>" >&2
  exit 2
}

[ "$#" -eq 5 ] || usage

TARGET_USER="$1"
TARGET_GROUP="$2"
TARGET_UID="$3"
TARGET_GID="$4"
TARGET_HOME="$5"

if [ "$TARGET_UID" = "0" ] || [ "$TARGET_GID" = "0" ]; then
  echo "create-user.sh: refusing PUID=0 or PGID=0 (root is not permitted in this stack)" >&2
  exit 1
fi

echo "create-user.sh: provisioning ${TARGET_USER}:${TARGET_GROUP} (${TARGET_UID}:${TARGET_GID}) home=${TARGET_HOME}"

# --- group ---------------------------------------------------------------
existing_group="$(getent group "$TARGET_GID" | cut -d: -f1 || true)"
if [ -n "$existing_group" ] && [ "$existing_group" != "$TARGET_GROUP" ]; then
  echo "create-user.sh: GID ${TARGET_GID} already belongs to group '${existing_group}' — renaming to '${TARGET_GROUP}'"
  groupmod -n "$TARGET_GROUP" "$existing_group"
elif [ -z "$existing_group" ]; then
  groupadd -g "$TARGET_GID" "$TARGET_GROUP"
fi
# else: group already exists with correct name+gid, nothing to do.

# --- user ------------------------------------------------------------------
existing_user="$(getent passwd "$TARGET_UID" | cut -d: -f1 || true)"
if [ -n "$existing_user" ] && [ "$existing_user" != "$TARGET_USER" ]; then
  echo "create-user.sh: UID ${TARGET_UID} already belongs to user '${existing_user}' — repurposing to '${TARGET_USER}'"
  mkdir -p "$(dirname "$TARGET_HOME")"
  usermod -l "$TARGET_USER" -d "$TARGET_HOME" -m -s /bin/bash "$existing_user"
  usermod -g "$TARGET_GID" "$TARGET_USER"
elif [ -z "$existing_user" ]; then
  useradd -u "$TARGET_UID" -g "$TARGET_GID" -d "$TARGET_HOME" -m -s /bin/bash "$TARGET_USER"
fi
# else: user already exists with correct name+uid, nothing to do.

# --- build-time verification ---------------------------------------------
id "$TARGET_USER" >/dev/null
actual_uid="$(id -u "$TARGET_USER")"
actual_gid="$(id -g "$TARGET_USER")"
if [ "$actual_uid" != "$TARGET_UID" ] || [ "$actual_gid" != "$TARGET_GID" ]; then
  echo "create-user.sh: FATAL — expected ${TARGET_UID}:${TARGET_GID}, got ${actual_uid}:${actual_gid}" >&2
  exit 1
fi

mkdir -p "$TARGET_HOME"
chown "${TARGET_UID}:${TARGET_GID}" "$TARGET_HOME"
owner_uid="$(stat -c '%u' "$TARGET_HOME")"
owner_gid="$(stat -c '%g' "$TARGET_HOME")"
if [ "$owner_uid" != "$TARGET_UID" ] || [ "$owner_gid" != "$TARGET_GID" ]; then
  echo "create-user.sh: FATAL — home dir ${TARGET_HOME} owned by ${owner_uid}:${owner_gid}, expected ${TARGET_UID}:${TARGET_GID}" >&2
  exit 1
fi

echo "create-user.sh: OK — ${TARGET_USER}:${TARGET_GROUP} verified at ${actual_uid}:${actual_gid}, home=${TARGET_HOME}"
