#!/bin/bash
## Build the architecture independent packages of openwrt/feed (LuCI apps,
## ucode / shell scripts: PKGARCH all) with the official x86/64 SDK, for the
## ImageBuilder images of every target.
##
## ENV
##   OW_VER=25.12.5     OpenWrt release
##   FEED_OUT=out/feed  where the .apk files go
##   WORK=build/ib      SDK / downloads

set -euo pipefail
. "$(dirname "$0")/common.sh"

PKGS="luci-app-zt-gateway luci-app-docker-apps khadas-wifi-autoconf"
HEAVY="dockerd docker docker-compose zerotier"
FEED_OUT=${FEED_OUT:-$IB_ROOT/out/feed}
SDK=$WORK/sdk-x86-64

fetch_tool sdk x86 64 "$SDK"
cd "$SDK"

github_feeds feeds.conf.default > feeds.conf
echo "src-link khadas $IB_TOP/feed" >> feeds.conf
log "feeds update"
./scripts/feeds update -a >/dev/null
./scripts/feeds install luci-base $PKGS >/dev/null
# runtime dependencies are compile dependencies in OpenWrt: without these
# (Go / C++, not needed to package scripts) the SDK would build all of
# docker and zerotier; the .apk files still depend on them
./scripts/feeds uninstall $HEAVY >/dev/null

# only the wanted packages, nothing else
: > .config
for p in $PKGS; do
	echo "CONFIG_PACKAGE_$p=m" >> .config
done
make defconfig >/dev/null

for p in $PKGS; do
	grep -q "^CONFIG_PACKAGE_$p=m" .config || die "$p not selectable in the SDK"
	log "compile $p"
	make "package/$p/compile" -j"$(nproc)" || make "package/$p/compile" -j1 V=s
done

rm -rf "$FEED_OUT"
mkdir -p "$FEED_OUT"
for p in $PKGS; do
	f=$(find bin/packages -path '*/khadas/*' -name "$p-[0-9]*.apk" | head -n 1)
	[ -n "$f" ] || die "no apk for $p"
	cp -v "$f" "$FEED_OUT/"
done
log "feed packages: $FEED_OUT"
ls -l "$FEED_OUT"
