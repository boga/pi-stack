#!/bin/bash
# install-roamgate.sh — download the pinned roamgate release tarball, verify
# it against its own published .sha256 sidecar, extract, assert VERSION,
# install, and bundle its MIT LICENSE (fetched from the same immutable git
# tag). Optionally runs a build-time `roamgate --version` smoke test —
# ONLY when explicitly requested (native-arch "runtime" target); the
# cross-arch "runtime-cross" target must never execute the binary at all.
#
# Usage: install-roamgate.sh <version e.g. 0.7.8> <targetarch: amd64|arm64> <run_smoke_test: 0|1>
set -euo pipefail

ROAMGATE_VERSION="${1:?roamgate version required, e.g. 0.7.8}"
TARGETARCH="${2:?targetarch required (amd64|arm64)}"
RUN_SMOKE_TEST="${3:-0}"

case "$TARGETARCH" in
  amd64) ASSET_ARCH="x64" ;;
  arm64) ASSET_ARCH="arm64" ;;
  *) echo "install-roamgate.sh: unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;;
esac

ARCHIVE="roamgate-linux-${ASSET_ARCH}.tar.xz"
BASE_URL="https://github.com/powerfooI/roamgate/releases/download/v${ROAMGATE_VERSION}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

curl -fsSL -o "$ARCHIVE" "${BASE_URL}/${ARCHIVE}"
curl -fsSL -o "${ARCHIVE}.sha256" "${BASE_URL}/${ARCHIVE}.sha256"

# sidecar format: "<64 hex>  <archive name>" — directly consumable by sha256sum -c
sha256sum -c "${ARCHIVE}.sha256"

tar -xJf "$ARCHIVE"

extracted_dir="roamgate-linux-${ASSET_ARCH}"
if [ ! -d "$extracted_dir" ]; then
  # fall back to whatever single directory was extracted
  extracted_dir="$(find . -mindepth 1 -maxdepth 1 -type d | head -n1)"
fi

if [ -L "${extracted_dir}/VERSION" ] || [ ! -f "${extracted_dir}/VERSION" ]; then
  echo "install-roamgate.sh: FATAL — VERSION file missing or is a symlink in ${extracted_dir}" >&2
  exit 1
fi
if [ -L "${extracted_dir}/roamgate" ] || [ ! -x "${extracted_dir}/roamgate" ]; then
  echo "install-roamgate.sh: FATAL — roamgate binary missing, not executable, or is a symlink" >&2
  exit 1
fi

installed_version_raw="$(cat "${extracted_dir}/VERSION")"
# VERSION file format observed upstream: "roamgate <semver> <platform>"
# (not a bare semver) — assert the pinned version appears in it rather
# than requiring an exact string match.
case " ${installed_version_raw} " in
  *" ${ROAMGATE_VERSION} "*) ;;
  *)
    echo "install-roamgate.sh: FATAL — VERSION file says '${installed_version_raw}', expected to contain '${ROAMGATE_VERSION}'" >&2
    exit 1
    ;;
esac

install -m 0755 "${extracted_dir}/roamgate" /usr/local/bin/roamgate

mkdir -p /usr/share/licenses/roamgate
curl -fsSL -o /usr/share/licenses/roamgate/LICENSE \
  "https://raw.githubusercontent.com/powerfooI/roamgate/v${ROAMGATE_VERSION}/LICENSE"

if [ "$RUN_SMOKE_TEST" = "1" ]; then
  echo "install-roamgate.sh: running native-arch smoke test (roamgate --version, bounded by 30s)"
  timeout -s KILL 30 /usr/local/bin/roamgate --version
else
  echo "install-roamgate.sh: cross-arch build — skipping binary execution, checksum verification only"
fi

echo "install-roamgate.sh: OK — roamgate v${ROAMGATE_VERSION} (${ARCHIVE}) installed and verified"
