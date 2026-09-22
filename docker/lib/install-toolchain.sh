#!/bin/bash
# install-toolchain.sh — shared apt toolchain + pinned gh/kubectl for the
# pi and herdr images (herdr needs it too: herdr spawns pane child processes
# inside ITS OWN container filesystem, so panes launched from roamgate need
# git/gh/kubectl/bash available in the herdr image, not just the pi image).
#
# Usage: install-toolchain.sh <targetarch: amd64|arm64> <gh_version e.g. 2.101.0> <kubectl_version e.g. v1.37.0>
set -euo pipefail

TARGETARCH="${1:?targetarch required (amd64|arm64)}"
GH_VERSION="${2:?gh version required, e.g. 2.101.0}"
KUBECTL_VERSION="${3:?kubectl version required, e.g. v1.37.0}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  openssh-client \
  bash \
  jq \
  less \
  procps \
  tar \
  xz-utils \
  tzdata
rm -rf /var/lib/apt/lists/*

case "$TARGETARCH" in
  amd64) GH_ARCH=amd64; KC_ARCH=amd64 ;;
  arm64) GH_ARCH=arm64; KC_ARCH=arm64 ;;
  *) echo "install-toolchain.sh: unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;;
esac

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

# --- gh (GitHub CLI) — pinned version, verified against release checksums.txt
GH_TARBALL="gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz"
GH_BASE_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}"
curl -fsSL -o "$GH_TARBALL" "${GH_BASE_URL}/${GH_TARBALL}"
curl -fsSL -o checksums.txt "${GH_BASE_URL}/gh_${GH_VERSION}_checksums.txt"
grep " ${GH_TARBALL}\$" checksums.txt | sha256sum -c -
tar -xzf "$GH_TARBALL"
install -m 0755 "gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /usr/local/bin/gh
mkdir -p /usr/share/licenses/gh
cp "gh_${GH_VERSION}_linux_${GH_ARCH}/LICENSE" /usr/share/licenses/gh/LICENSE

# --- kubectl — pinned version, verified against its official .sha256 sidecar
KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KC_ARCH}/kubectl"
curl -fsSL -o kubectl "$KUBECTL_URL"
curl -fsSL -o kubectl.sha256 "${KUBECTL_URL}.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c -
install -m 0755 kubectl /usr/local/bin/kubectl
mkdir -p /usr/share/licenses/kubectl
# Fetch the real Apache-2.0 license text from the kubernetes/kubernetes repo
# at the exact pinned tag (kubectl ships from that monorepo and is licensed
# under it), rather than just a NOTE pointing at it.
curl -fsSL -o /usr/share/licenses/kubectl/LICENSE \
  "https://raw.githubusercontent.com/kubernetes/kubernetes/${KUBECTL_VERSION}/LICENSE"

gh --version
kubectl version --client
