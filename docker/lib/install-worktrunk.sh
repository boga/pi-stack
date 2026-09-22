#!/bin/bash
# install-worktrunk.sh — download the pinned worktrunk (`wt`) release,
# verify its sha256 against the upstream-published sidecar, install it,
# and bundle its real dual-license (MIT OR Apache-2.0) LICENSE text.
#
# Uses upstream's prebuilt static musl binaries (worktrunk-*-unknown-linux-musl
# .tar.xz) rather than a glibc build — musl static binaries run unmodified on
# both this stack's Debian (glibc) base images and would run on Alpine too,
# so there's no glibc/musl matching concern here.
#
# Usage: install-worktrunk.sh <version e.g. 0.79.0> <targetarch: amd64|arm64>
set -euo pipefail

WORKTRUNK_VERSION="${1:?worktrunk version required, e.g. 0.79.0}"
TARGETARCH="${2:?targetarch required (amd64|arm64)}"

case "$TARGETARCH" in
  amd64) ASSET="worktrunk-x86_64-unknown-linux-musl" ;;
  arm64) ASSET="worktrunk-aarch64-unknown-linux-musl" ;;
  *)
    echo "install-worktrunk.sh: unsupported TARGETARCH=$TARGETARCH" >&2
    exit 1
    ;;
esac

ARCHIVE="${ASSET}.tar.xz"
BASE_URL="https://github.com/max-sixty/worktrunk/releases/download/v${WORKTRUNK_VERSION}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

curl -fsSL -o "$ARCHIVE" "${BASE_URL}/${ARCHIVE}"
curl -fsSL -o "${ARCHIVE}.sha256" "${BASE_URL}/${ARCHIVE}.sha256"

# Sidecar format is "<sha256> *<filename>" — sha256sum -c reads it directly
# as long as the file on disk has the exact name the sidecar references.
sha256sum -c "${ARCHIVE}.sha256"

tar -xJf "$ARCHIVE"
install -m 0755 "${ASSET}/wt" /usr/local/bin/wt

mkdir -p /usr/share/licenses/worktrunk
cp "${ASSET}/LICENSE" /usr/share/licenses/worktrunk/LICENSE

wt --version
echo "install-worktrunk.sh: OK — worktrunk v${WORKTRUNK_VERSION} (${ASSET}) installed and verified"
