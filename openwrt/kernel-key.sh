#!/bin/bash
## Key of a source built Edge-V kernel: hash of everything the kernel, the
## ImageBuilder and the kmod apk repository of openwrt/build.sh depend on.
## The CI builds the kernel only when no release kernel-<release>-<variant>-<key>
## exists in the kernel repository (220242/khadas-kernels) yet.
##
## USAGE
##   ./openwrt/kernel-key.sh edge-v|edge-v-kvm
##
## Rebuild without a change: bump openwrt/kernel-rev.
## Not in the key: CONFIG_PACKAGE_ lines of the diffconfigs (packages come
## from the ImageBuilder), the SDK built feed packages (openwrt/ib/sdk-feed.sh)

set -euo pipefail
cd "$(dirname "$0")/.."

VARIANT=${1:-}
case "$VARIANT" in
	edge-v) dirs="openwrt/patches"; cfgs="openwrt/diffconfig" ;;
	edge-v-kvm) dirs="openwrt/patches openwrt/patches-kvm"; cfgs="openwrt/diffconfig openwrt/diffconfig-kvm" ;;
	*) echo "usage: $0 edge-v|edge-v-kvm" >&2; exit 1 ;;
esac
# architecture specific packages of the own feed, built with the kernel
feeds="openwrt/feed/khadas-edge-display openwrt/feed/khadas-storage
       openwrt/feed/luci-app-khadas-storage openwrt/feed/luci-app-kvm"

{
	echo "release ${OW_REL:-v25.12.5} $VARIANT"
	cat openwrt/kernel-rev
	cat $cfgs | grep -v -e '^CONFIG_PACKAGE_' -e '^#' -e '^[[:space:]]*$' | LC_ALL=C sort
	find $dirs $feeds -type f | LC_ALL=C sort | xargs sha256sum
} | sha256sum | cut -c1-12
