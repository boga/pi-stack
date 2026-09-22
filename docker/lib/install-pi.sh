#!/bin/bash
# install-pi.sh — install the pi coding agent npm package and bundle its
# license text. Package name uses a HYPHEN in "earendil-works", not a dot.
#
# Usage: install-pi.sh <version e.g. 0.87.0>
set -euo pipefail

PI_VERSION="${1:?pi package version required, e.g. 0.87.0}"
PACKAGE="@earendil-works/pi-coding-agent"

npm install -g "${PACKAGE}@${PI_VERSION}"

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
  echo "install-pi.sh: WARNING — no LICENSE file found in $pkg_dir; recording package metadata only" >&2
  node -e "console.log(require('${pkg_dir}/package.json').license || 'UNKNOWN')" > /usr/share/licenses/pi/LICENSE-SPDX-ID.txt
fi

pi --version
