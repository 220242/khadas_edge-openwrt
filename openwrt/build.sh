#!/bin/bash

## OpenWrt 25.12 source build for Khadas Edge / Edge-V / Edge-Captain (RK3399)
##
## USAGE
##   ./openwrt/build.sh            # prepare + download + build
##   ./openwrt/build.sh prepare    # clone, patch, feeds, .config only
##   ./openwrt/build.sh download   # prepare + download sources
##
## ENV
##   OW_REL=v25.12.5   OpenWrt release tag
##   SRC=build/openwrt OpenWrt source tree
##   JOBS=$(nproc)
##   OUT=out           images output directory
##   ZT_CONTROLLER=1   add the ZeroTier network controller (ZeroTier
##                     Source-Available License: non-commercial use only,
##                     do not distribute such images)

set -euo pipefail

TOP=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TOP/.." && pwd)

OW_REL=${OW_REL:-v25.12.5}
OW_GIT=${OW_GIT:-https://github.com/openwrt/openwrt.git}
SRC=${SRC:-$ROOT/build/openwrt}
JOBS=${JOBS:-$(nproc)}
OUT=${OUT:-$ROOT/out}
STEP=${1:-all}

log() { echo "[i] $*" >&2; }
die() { echo "[e] $*" >&2; exit 1; }

# apply patch once (skip if already applied)
apply_patch() {
	local dir="$1" patch="$2"
	if git -C "$dir" apply --check "$patch" 2>/dev/null; then
		log "apply $(basename "$patch")"
		git -C "$dir" apply "$patch"
	elif git -C "$dir" apply --reverse --check "$patch" 2>/dev/null; then
		log "already applied $(basename "$patch")"
	else
		die "patch $patch does not apply to $dir"
	fi
}

## source
if [ ! -d "$SRC/.git" ]; then
	log "clone OpenWrt $OW_REL -> $SRC"
	mkdir -p "$(dirname "$SRC")"
	git clone --depth 1 --branch "$OW_REL" "$OW_GIT" "$SRC"
fi

cd "$SRC"

for p in "$TOP"/patches/*.patch; do
	apply_patch "$SRC" "$p"
done

## feeds: release pinned commits, github mirrors + local feed
sed -e 's#https://git.openwrt.org/feed/packages.git#https://github.com/openwrt/packages.git#' \
    -e 's#https://git.openwrt.org/project/luci.git#https://github.com/openwrt/luci.git#' \
    -e 's#https://git.openwrt.org/feed/routing.git#https://github.com/openwrt/routing.git#' \
    -e 's#https://git.openwrt.org/feed/telephony.git#https://github.com/openwrt/telephony.git#' \
    feeds.conf.default > feeds.conf
echo "src-link khadas $TOP/feed" >> feeds.conf

log "feeds update"
./scripts/feeds update -a

for d in "$TOP"/patches/feeds/*/; do
	feed=$(basename "$d")
	for p in "$d"*.patch; do
		[ -f "$p" ] || continue
		apply_patch "$SRC/feeds/$feed" "$p"
	done
done

log "feeds install"
./scripts/feeds update -i
./scripts/feeds install -a

## files overlay
rm -rf "$SRC/files"
cp -a "$TOP/files" "$SRC/files"

## config
cp "$TOP/diffconfig" .config
if [ "${ZT_CONTROLLER:-0}" = 1 ]; then
	log "ZeroTier network controller enabled: non-commercial license, private use only"
	echo "CONFIG_ZEROTIER_ENABLE_CONTROLLER=y" >> .config
fi
make defconfig

# check that all requested packages survived defconfig
missing=
while read -r line; do
	case "$line" in
		CONFIG_*=y)
		sym=${line%=y}
		grep -q "^$sym=y" .config || missing="$missing $sym"
		;;
	esac
done < "$TOP/diffconfig"
[ -z "$missing" ] || die "not selected after defconfig:$missing"
if [ "${ZT_CONTROLLER:-0}" = 1 ]; then
	grep -q '^CONFIG_ZEROTIER_ENABLE_CONTROLLER=y' .config || die "ZeroTier controller not selected"
fi

[ "$STEP" = "prepare" ] && exit 0

log "download sources"
make download -j8 || make download -j1 V=s

[ "$STEP" = "download" ] && exit 0

log "build with $JOBS jobs"
make -j"$JOBS" || make -j1 V=s

mkdir -p "$OUT"
cp -v bin/targets/rockchip/armv8/*khadas*.img.gz "$OUT"/
cp -v bin/targets/rockchip/armv8/sha256sums "$OUT"/ 2>/dev/null || true
cp -v bin/targets/rockchip/armv8/*.manifest "$OUT"/ 2>/dev/null || true

log "DONE: $OUT"
ls -l "$OUT"
