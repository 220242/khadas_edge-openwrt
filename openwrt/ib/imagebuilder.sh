#!/bin/bash
## x86 images with the official OpenWrt ImageBuilder: official kernel and
## kmods (apk add kmod-... works from downloads.openwrt.org), the packages of
## openwrt/ib/packages/*.list and the own feed packages (sdk-feed.sh).
##
## USAGE
##   ./openwrt/ib/imagebuilder.sh VARIANT
##
##   x86-64-pc     PC / server x86_64 (UEFI + BIOS): Wi-Fi, 4G/5G, Docker, NICs
##   x86-64-vm     virtual machine x86_64: Proxmox / QEMU (qcow2), VMware
##                 (vmdk), VirtualBox (vdi), Hyper-V (vhdx), raw (img.gz)
##   i386-pc       32-bit PC, Pentium 4 and newer (BIOS)
##   i386-legacy   very old 32-bit PC: i486 / Pentium / Pentium III (BIOS)
##
## ENV
##   OW_VER=25.12.5      OpenWrt release
##   FEED_OUT=out/feed   own feed packages (.apk, from sdk-feed.sh)
##   OUT=out             images go to $OUT/VARIANT
##   WORK=build/ib       ImageBuilders / downloads

set -euo pipefail
. "$(dirname "$0")/common.sh"

VARIANT=${1:-}
FEED_OUT=${FEED_OUT:-$IB_ROOT/out/feed}
OUT=${OUT:-$IB_ROOT/out}

case "$VARIANT" in
	x86-64-pc)   T=x86 S=64      LISTS="base wifi modem docker nic" SIZE=1024 ;;
	x86-64-vm)   T=x86 S=64      LISTS="base docker vm"             SIZE=1024 ;;
	i386-pc)     T=x86 S=generic LISTS="base wifi modem nic"        SIZE=512 ;;
	i386-legacy) T=x86 S=legacy  LISTS="base legacy"                SIZE=256 ;;
	*) sed -n 's/^## \{0,1\}//p' "$0" >&2; exit 1 ;;
esac

IB=$WORK/imagebuilder-$T-$S
DEST=$OUT/$VARIANT
fetch_tool imagebuilder "$T" "$S" "$IB"

## own feed packages
rm -rf "$IB/packages"
mkdir -p "$IB/packages"
if ls "$FEED_OUT"/*.apk >/dev/null 2>&1; then
	cp "$FEED_OUT"/*.apk "$IB/packages/"
else
	die "no feed packages in $FEED_OUT (run openwrt/ib/sdk-feed.sh)"
fi

## packages available for this target: index.json of every repository
avail=$WORK/avail-$T-$S.txt
: > "$avail"
repos=$(grep -hoE 'https?://[^ "]+/packages\.adb' "$IB"/repositories* 2>/dev/null | sort -u || true)
for r in $repos; do
	curl -fsSL --retry 3 "${r%packages.adb}index.json" 2>/dev/null |
		python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["packages"]))' >> "$avail" || \
		log "no index.json for $r"
done
for f in "$IB"/packages/*.apk; do
	basename "$f" | sed -E 's/-[0-9][^-]*(-r[0-9]+)?\.apk$//'
done >> "$avail"
[ -s "$avail" ] || log "package index not readable, not checking optional packages"

## package list
pkgs=""
for l in $LISTS; do
	while read -r p; do
		case "$p" in
			""|\#*) continue ;;
			-*) pkgs="$pkgs $p" ;;
			\?*)
				p=${p#\?}
				if [ ! -s "$avail" ] || grep -qx "$p" "$avail"; then
					pkgs="$pkgs $p"
				else
					log "optional package $p not available for $T/$S, skipped"
				fi
				;;
			*) pkgs="$pkgs $p" ;;
		esac
	done < "$IB_TOP/ib/packages/$l.list"
done

## first boot defaults: single network port = DHCP uplink, Docker firewall
FILES=$WORK/files-$VARIANT
rm -rf "$FILES"
mkdir -p "$FILES/etc/uci-defaults"
cp "$IB_TOP/files/etc/uci-defaults/96-docker-firewall" \
   "$IB_TOP/files/etc/uci-defaults/98-khadas-network" "$FILES/etc/uci-defaults/"

log "$VARIANT: $T/$S, packages:$pkgs"
BIN=$WORK/bin-$VARIANT
rm -rf "$BIN"
make -C "$IB" image PROFILE=generic PACKAGES="$pkgs" FILES="$FILES" \
	ROOTFS_PARTSIZE="$SIZE" BIN_DIR="$BIN"

## canonical file names
rm -rf "$DEST"
mkdir -p "$DEST"
name=openwrt-$OW_VER-$VARIANT
efi=$(ls "$BIN"/*squashfs-combined-efi.img.gz 2>/dev/null | head -n 1 || true)
bios=$(ls "$BIN"/*squashfs-combined.img.gz 2>/dev/null | head -n 1 || true)
[ -n "$efi$bios" ] || die "no image in $BIN"
cp "$(ls "$BIN"/*.manifest | head -n 1)" "$DEST/$name.manifest"

case "$VARIANT" in
	x86-64-pc)
		cp "$efi" "$DEST/$name-efi.img.gz"
		cp "$bios" "$DEST/$name-bios.img.gz"
		;;
	x86-64-vm)
		# GPT image with GRUB for UEFI (OVMF) and BIOS (SeaBIOS)
		cp "$efi" "$DEST/$name.img.gz"
		raw=$WORK/$name.img
		gzip -dc "$efi" > "$raw" 2>/dev/null || true	# trailing metadata
		[ -s "$raw" ] || die "can not unpack $efi"
		qemu-img convert -f raw -O qcow2 -c "$raw" "$DEST/$name.qcow2"
		qemu-img convert -f raw -O vmdk "$raw" "$DEST/$name.vmdk"
		qemu-img convert -f raw -O vdi "$raw" "$DEST/$name.vdi"
		qemu-img convert -f raw -O vhdx -o subformat=dynamic "$raw" "$DEST/$name.vhdx"
		rm -f "$raw"
		;;
	i386-*)
		cp "${bios:-$efi}" "$DEST/$name-bios.img.gz"
		;;
esac

(cd "$DEST" && sha256sum -- * > "sha256sums-$VARIANT")
log "DONE: $DEST"
ls -l "$DEST"
