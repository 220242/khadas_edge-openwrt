#!/bin/bash
## Build the architecture specific own packages of the Edge-V on the
## official kernel (edge-v-official) with the official rockchip/armv8 SDK:
##   kmod-drm-rockchip     Rockchip DRM (VOP + DW HDMI) as external modules
##                         of the official kernel (openwrt/feed-official)
##   khadas-edge-console   login + addresses on the HDMI screen
##   khadas-storage, luci-app-khadas-storage
##                         install to a USB SSD / NVMe, boot from it
## The .apk files go to FEED_OUT next to the packages of sdk-feed.sh.
##
## ENV
##   OW_VER=            OpenWrt release (default: openwrt/version)
##   FEED_OUT=out/feed  where the .apk files go
##   WORK=build/ib      SDK / downloads

set -euo pipefail
. "$(dirname "$0")/common.sh"

# source package -> binary packages
SRC_PKGS="khadas-edge-hdmi khadas-storage luci-app-khadas-storage"
PKGS="kmod-drm-rockchip khadas-edge-console khadas-storage luci-app-khadas-storage"
# run time dependencies of khadas-storage (official packages): without these
# the SDK would compile util-linux, f2fs-tools, e2fsprogs; the .apk files
# still depend on them
HEAVY="util-linux f2fs-tools e2fsprogs fwtool"
FEED_OUT=${FEED_OUT:-$IB_ROOT/out/feed}
SDK=$WORK/sdk-rockchip-armv8

fetch_tool sdk rockchip armv8 "$SDK"
cd "$SDK"

# khadas-storage builds its boot script with the U-Boot mkimage
[ -x staging_dir/host/bin/mkimage ] || {
	command -v mkimage >/dev/null || die "no mkimage (u-boot-tools)"
	ln -sf "$(command -v mkimage)" staging_dir/host/bin/mkimage
}

github_feeds feeds.conf.default > feeds.conf
# the official kernel versions of the source build packages first
echo "src-link khadasofc $IB_TOP/feed-official" >> feeds.conf
echo "src-link khadas $IB_TOP/feed" >> feeds.conf
log "feeds update"
./scripts/feeds update -a >/dev/null
./scripts/feeds install luci-base >/dev/null
./scripts/feeds install -p khadasofc kmod-drm-rockchip khadas-edge-console >/dev/null
./scripts/feeds install -p khadas khadas-storage luci-app-khadas-storage >/dev/null
./scripts/feeds uninstall $HEAVY >/dev/null

: > .config
for p in $PKGS; do
	echo "CONFIG_PACKAGE_$p=m" >> .config
done
make defconfig >/dev/null
for p in $PKGS; do
	grep -q "^CONFIG_PACKAGE_$p=m" .config || die "$p not selectable in the SDK"
done

# the official kernel: what the external modules link against
kcfg=$(ls build_dir/target-*/linux-*/linux-*/.config | head -n 1)
log "official kernel $(basename "$(dirname "$kcfg")"): $(grep -E \
	'^CONFIG_(DRM|DRM_KMS_HELPER|DRM_GEM_DMA_HELPER|DRM_FBDEV_EMULATION|FB|FRAMEBUFFER_CONSOLE|DRM_DISPLAY_HELPER|DRM_ROCKCHIP)=' \
	"$kcfg" | tr '\n' ' ')"
grep -q '^CONFIG_DRM_FBDEV_EMULATION=y' "$kcfg" || die "official kernel without DRM fbdev emulation"
grep -q '^CONFIG_FRAMEBUFFER_CONSOLE=y' "$kcfg" || die "official kernel without framebuffer console"
grep -q '^CONFIG_DRM_ROCKCHIP=' "$kcfg" && die "official kernel has Rockchip DRM now, use its kmod"

for p in $SRC_PKGS; do
	log "compile $p"
	make "package/$p/compile" -j"$(nproc)" || make "package/$p/compile" -j1 V=s
done

mkdir -p "$FEED_OUT"
for p in $PKGS; do
	f=$(find bin -name "$p-[0-9]*.apk" | head -n 1)
	[ -n "$f" ] || die "no apk for $p"
	cp -v "$f" "$FEED_OUT/"
done

# the modules are in the package, built for this kernel
f=$(ls "$FEED_OUT"/kmod-drm-rockchip-*.apk)
x=$WORK/kmod-check
rm -rf "$x"
mkdir -p "$x"
staging_dir/host/bin/apk extract --allow-untrusted --destination "$x" "$f"
kver=$(basename "$(dirname "$kcfg")")
kver=${kver#linux-}
for m in dw-hdmi rockchipdrm; do
	ko=$(find "$x/lib/modules" -name "$m.ko")
	[ -n "$ko" ] || die "$(basename "$f"): no $m.ko"
	strings "$ko" | grep -q "^vermagic=$kver " || die "$m.ko: not built for $kver"
done
log "$(basename "$f"): $(cd "$x" && find lib -type f | tr '\n' ' ')"

log "board packages: $FEED_OUT"
ls -l "$FEED_OUT"
