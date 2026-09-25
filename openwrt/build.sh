#!/bin/bash

## OpenWrt 25.12 source build for Khadas Edge-V (RK3399)
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
##   OUT=out           images output directory, the apk repository (every
##                     kmod + the khadas feed) goes to $OUT/apk-repo[-kvm]
##   APK_REPO_URL=     where $OUT/apk-repo gets published (https, apk
##                     repository root); the image then installs kmods from
##                     there, empty: the kmod / khadas feeds are disabled
##   KVM=1             virtual machines (KVM kernel, QEMU, luci-app-kvm):
##                     openwrt/patches-kvm + diffconfig-kvm, images named
##                     ...khadas_edge-v-kvm-..., default SRC build/openwrt-kvm
##   ZT_CONTROLLER=1   add the ZeroTier network controller (ZeroTier
##                     Source-Available License: non-commercial use only,
##                     do not distribute such images)

set -euo pipefail

TOP=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TOP/.." && pwd)

OW_REL=${OW_REL:-v25.12.5}
OW_GIT=${OW_GIT:-https://github.com/openwrt/openwrt.git}
KVM=${KVM:-0}
VSUFFIX=
[ "$KVM" = 1 ] && VSUFFIX=-kvm
SRC=${SRC:-$ROOT/build/openwrt$VSUFFIX}
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
# init + fetch instead of clone: $SRC may already hold dl/ (CI cache)
if [ ! -d "$SRC/.git" ]; then
	log "clone OpenWrt $OW_REL -> $SRC"
	mkdir -p "$SRC"
	git -C "$SRC" init -q
	git -C "$SRC" remote add origin "$OW_GIT"
	git -C "$SRC" fetch --depth 1 origin tag "$OW_REL"
	git -C "$SRC" checkout -q "$OW_REL"
fi

cd "$SRC"

PATCHES="$TOP/patches"
[ "$KVM" = 1 ] && PATCHES="$PATCHES $TOP/patches-kvm"
for d in $PATCHES; do
	for p in "$d"/*.patch; do
		apply_patch "$SRC" "$p"
	done
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

for pd in $PATCHES; do
	for d in "$pd"/feeds/*/; do
		[ -d "$d" ] || continue
		feed=$(basename "$d")
		for p in "$d"*.patch; do
			[ -f "$p" ] || continue
			apply_patch "$SRC/feeds/$feed" "$p"
		done
	done
done

log "feeds install"
./scripts/feeds update -i
./scripts/feeds install -a

## files overlay
rm -rf "$SRC/files"
cp -a "$TOP/files" "$SRC/files"
if [ -n "${APK_REPO_URL:-}" ]; then
	log "kmod repository: $APK_REPO_URL"
	echo "${APK_REPO_URL%/}" > "$SRC/files/etc/khadas-apk-repo"
fi

## config
cp "$TOP/diffconfig" .config
CONFIGS="$TOP/diffconfig"
if [ "$KVM" = 1 ]; then
	log "KVM variant"
	cat "$TOP/diffconfig-kvm" >> .config
	CONFIGS="$CONFIGS $TOP/diffconfig-kvm"
fi
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
done < <(cat $CONFIGS)
[ -z "$missing" ] || die "not selected after defconfig:$missing"
if [ "${ZT_CONTROLLER:-0}" = 1 ]; then
	grep -q '^CONFIG_ZEROTIER_ENABLE_CONTROLLER=y' .config || die "ZeroTier controller not selected"
fi

[ "$STEP" = "prepare" ] && exit 0

log "download sources"
make download -j8 || make download -j1 V=s

[ "$STEP" = "download" ] && exit 0

log "build with $JOBS jobs"
# IGNORE_ERRORS=m: a kmod that fails to build is only missing from the apk
# repository (as on the OpenWrt buildbot), the image packages (=y) must build
make -j"$JOBS" IGNORE_ERRORS=m || make -j1 V=s IGNORE_ERRORS=m

mkdir -p "$OUT"
# KVM images get their own names (both variants in one release)
name() { local b; b=$(basename "$1"); echo "${b/khadas_edge-v/khadas_edge-v$VSUFFIX}"; }
for f in bin/targets/rockchip/armv8/*khadas*.img.gz bin/targets/rockchip/armv8/*.manifest; do
	[ -f "$f" ] && cp -v "$f" "$OUT/$(name "$f")"
done
(cd "$OUT" && sha256sum -- *khadas_edge-v*.img.gz > sha256sums)

# apk repository matching this kernel: kmods + target packages, khadas feed
REPO="$OUT/apk-repo$VSUFFIX"
rm -rf "$REPO"
mkdir -p "$REPO/targets" "$REPO/khadas"
cp -a bin/targets/rockchip/armv8/packages/. "$REPO/targets/"
cp -a bin/packages/*/khadas/. "$REPO/khadas/"
# kmods of the other feeds belong to this kernel too (the buildbot moves
# them into its kmods feed), index + sign again like package/index
find bin/packages -name 'kmod-*.apk' ! -path '*/khadas/*' -exec cp -a {} "$REPO/targets/" \;
TOPDIR=$(pwd)
(
	cd "$REPO/targets"
	rm -f packages.adb index.json
	"$TOPDIR/staging_dir/host/bin/apk" mkndx --root "$TOPDIR" --keys-dir "$TOPDIR" \
		--allow-untrusted --sign "$TOPDIR/private-key.pem" --output packages.adb *.apk
)
[ -f "$REPO/targets/packages.adb" ] || die "no packages.adb in $REPO/targets"
[ -f "$REPO/khadas/packages.adb" ] || die "no packages.adb in $REPO/khadas"
log "apk repository: $REPO ($(find "$REPO" -name '*.apk' | wc -l) packages, $(du -sh "$REPO" | cut -f1))"

log "DONE: $OUT"
ls -l "$OUT"
