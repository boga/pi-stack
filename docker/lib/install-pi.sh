#!/bin/bash
# install-pi.sh — install the pi coding agent npm package and bundle its
# license text. Package name uses a HYPHEN in "earendil-works", not a dot.
#
# Usage: install-pi.sh <version e.g. 0.87.0>
set -euo pipefail

PI_VERSION="${1:?pi package version required, e.g. 0.87.0}"
PACKAGE="@earendil-works/pi-coding-agent"

# --allow-scripts is explicit, not incidental: npm >=11 (bundled with
# Node 24+) gates lifecycle scripts of *transitive* dependencies behind
# an allowlist by default (npm <11, e.g. Node 22's bundled npm 10, ran
# them unconditionally). Confirmed empirically that pi's own bundled
# dist/bundle/cli.js never references esbuild (0 matches) and the
# vendored esbuild binary runs fine even without its postinstall — so
# this isn't fixing an observed break, it's matching the previous
# npm-10 behavior exactly rather than relying on "seems to work anyway".
npm install -g --allow-scripts=esbuild,protobufjs,@google/genai "${PACKAGE}@${PI_VERSION}"

pkg_dir="$(npm root -g)/${PACKAGE}"
if [ ! -d "$pkg_dir" ]; then
  echo "install-pi.sh: FATAL — expected package dir not found: $pkg_dir" >&2
  exit 1
fi

mkdir -p /usr/share/licenses/pi
license_file="$(find "$pkg_dir" -maxdepth 1 -iname 'LICENSE*' | head -n1)"
if [ -n "$license_file" ]; then
  cp "$license_file" /usr/share/licenses/pi/LICENSE
else
  # The published npm tarball for @earendil-works/pi-coding-agent does not
  # include a LICENSE file (confirmed empirically: `npm pack` + `tar tzf`
  # show no LICENSE/LICENSE.md/COPYING entry as of 0.87.0), even though
  # package.json declares "license": "MIT". Fetch the real MIT license
  # text from the upstream source repo at the matching git tag instead of
  # writing an SPDX-identifier stub, so a real license text is always
  # bundled.
  echo "install-pi.sh: no LICENSE file in npm package; fetching real MIT text from upstream source repo tag v${PI_VERSION}" >&2
  if ! curl -fsSL -o /usr/share/licenses/pi/LICENSE \
      "https://raw.githubusercontent.com/earendil-works/pi/v${PI_VERSION}/LICENSE"; then
    echo "install-pi.sh: FATAL — could not fetch LICENSE from https://raw.githubusercontent.com/earendil-works/pi/v${PI_VERSION}/LICENSE" >&2
    exit 1
  fi
fi

pi --version
