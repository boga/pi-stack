#!/bin/bash
# install-herdr.sh — download the pinned herdr binary, verify its sha256,
# install it, and bundle its Apache-2.0 LICENSE (fetched from the same
# immutable git tag as the binary — there is no upstream root NOTICE file
# to propagate for this release).
#
# Usage: install-herdr.sh <version e.g. 0.9.1> <targetarch: amd64|arm64> <sha256_amd64> <sha256_arm64>
set -euo pipefail

HERDR_VERSION="${1:?herdr version required, e.g. 0.9.1}"
TARGETARCH="${2:?targetarch required (amd64|arm64)}"
SHA256_AMD64="${3:-}"
SHA256_ARM64="${4:-}"

case "$TARGETARCH" in
  amd64)
    ASSET="herdr-linux-x86_64"
    EXPECTED_SHA256="$SHA256_AMD64"
    ;;
  arm64)
    ASSET="herdr-linux-aarch64"
    EXPECTED_SHA256="$SHA256_ARM64"
    ;;
  *)
    echo "install-herdr.sh: unsupported TARGETARCH=$TARGETARCH" >&2
    exit 1
    ;;
esac

if [ -z "$EXPECTED_SHA256" ]; then
  echo "install-herdr.sh: FATAL — no pinned sha256 provided for TARGETARCH=$TARGETARCH (refusing to install unverified binary)" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

URL="https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/${ASSET}"
curl -fsSL -o herdr "$URL"

actual_sha256="$(sha256sum herdr | awk '{print $1}')"
if [ "$actual_sha256" != "$EXPECTED_SHA256" ]; then
  echo "install-herdr.sh: FATAL — sha256 mismatch for ${ASSET}" >&2
  echo "  expected: $EXPECTED_SHA256" >&2
  echo "  actual:   $actual_sha256" >&2
  exit 1
fi

install -m 0755 herdr /usr/local/bin/herdr

mkdir -p /usr/share/licenses/herdr
curl -fsSL -o /usr/share/licenses/herdr/LICENSE \
  "https://raw.githubusercontent.com/herdrdev/herdr/v${HERDR_VERSION}/LICENSE"

/usr/local/bin/herdr --version
echo "install-herdr.sh: OK — herdr v${HERDR_VERSION} (${ASSET}) installed and verified"
