#!/bin/bash
## Switch to another OpenWrt release: openwrt/version (read by build.sh,
## kernel-key.sh, ib/*.sh and the CI) and the version in the docs.
##
## USAGE
##   ./openwrt/set-version.sh 25.12.6
##
## A new release changes the kernel key: the CI builds the Edge-V kernels
## (~2 h) on the next push. Check the patches (openwrt/patches*) first with
## ./openwrt/build.sh prepare. A new series (26.x) also changes "OpenWrt 25.12"
## in the docs, the firmware selector and the Windows script.

set -euo pipefail
cd "$(dirname "$0")/.."

NEW=${1:-}
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]] ||
	{ sed -n 's/^## \{0,1\}//p' "$0" >&2; exit 1; }
OLD=$(cat openwrt/version)
[ "$NEW" != "$OLD" ] || { echo "already $OLD"; exit 0; }

# 25.12.5 -> 25.12.6 in file names and examples; dots are literal
re() { printf '%s' "$1" | sed 's/\./\\./g'; }
sed -i "s/$(re "$OLD")/$NEW/g" README.md
echo "$NEW" > openwrt/version

old_series=${OLD%.*} new_series=${NEW%.*}
new_series=${new_series%-rc*}
if [ "$old_series" != "$new_series" ]; then
	sed -i "s/OpenWrt $(re "$old_series")/OpenWrt $new_series/g" \
		README.md openwrt/build.sh openwrt/diffconfig selector/index.html \
		windows/build-khadas-edge.ps1
fi

echo "OpenWrt $OLD -> $NEW:"
git status --short
