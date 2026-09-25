#!/bin/bash
## Images with the official OpenWrt ImageBuilder: official kernel and kmods
## (apk add kmod-... works from downloads.openwrt.org), the packages of
## openwrt/ib/packages/*.list and the own feed packages (sdk-feed.sh).
##
## USAGE
##   ./openwrt/ib/imagebuilder.sh VARIANT
##
##   x86-64-pc       PC / server x86_64 (UEFI + BIOS): Wi-Fi, 4G/5G, Docker, NICs
##   x86-64-vm       virtual machine x86_64: Proxmox / QEMU (qcow2), VMware
##                   (vmdk), VirtualBox (vdi), Hyper-V (vhdx), raw (img.gz)
##   i386-pc         32-bit PC, Pentium 4 and newer (BIOS)
##   edge-v-official Khadas Edge-V on the official rockchip kernel (no HDMI
##                   console, no root on USB SSD, official kmods)
##   nanopi-r5c      FriendlyElec NanoPi R5C
##   nanopi-zero2    FriendlyElec NanoPi Zero2 (RK3528, device added here)
##   orangepi-zero2  Xunlong Orange Pi Zero2 (H616)
##   rpi-zero        Raspberry Pi Zero / Zero W
##   rpi-zero2       Raspberry Pi Zero 2 W
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
BOARD=
HOST=openwrt
SSID=OpenWrt

case "$VARIANT" in
	x86-64-pc)
		T=x86 S=64 PROFILE=generic SIZE=1024 HOST=openwrt-pc
		LISTS="base wificore wifipci wifiusb modem docker nic" ;;
	x86-64-vm)
		T=x86 S=64 PROFILE=generic SIZE=1024 HOST=openwrt-vm
		LISTS="base docker vm" ;;
	i386-pc)
		T=x86 S=generic PROFILE=generic SIZE=512 HOST=openwrt-i386
		LISTS="base wificore wifipci wifiusb modem nic" ;;
	edge-v-official)
		T=rockchip S=armv8 PROFILE=khadas_edge-v BOARD=khadas-edge-v SIZE=1024
		HOST=khadas-edge SSID=Khadas-Edge
		LISTS="base wificore wifipci wifiusb modem docker" ;;
	nanopi-r5c)
		T=rockchip S=armv8 PROFILE=friendlyarm_nanopi-r5c SIZE=1024 HOST=nanopi-r5c
		LISTS="base wificore wifipci wifiusb modem docker" ;;
	nanopi-zero2)
		T=rockchip S=armv8 PROFILE=friendlyarm_nanopi-zero2 BOARD=nanopi-zero2 SIZE=1024
		HOST=nanopi-zero2 LISTS="base wificore wifiusb docker" ;;
	orangepi-zero2)
		T=sunxi S=cortexa53 PROFILE=xunlong_orangepi-zero2 SIZE=1024 HOST=orangepi-zero2
		LISTS="base wificore wifiusb docker" ;;
	rpi-zero)
		T=bcm27xx S=bcm2708 PROFILE=rpi SIZE=512 HOST=rpi-zero
		LISTS="base wificore wifiusb" ;;
	rpi-zero2)
		T=bcm27xx S=bcm2710 PROFILE=rpi-3 SIZE=512 HOST=rpi-zero2
		LISTS="base wificore wifiusb" ;;
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

## a board OpenWrt does not have yet: device definition, profile, U-Boot,
## kernel (official Image + the board dtb as FIT) from boards/BOARD
inject_board() {
	local dir="$IB_ROOT/boards/$1"
	local DEVICE SOC LOADADDR VENDOR MODEL DTB UBOOT PACKAGES
	. "$dir/board.conf"
	local mk="$IB/target/linux/$T/image/$S.mk"
	local kdir kver tmp

	grep -q "^define Device/$DEVICE\$" "$mk" && return 0
	log "add device $DEVICE ($VENDOR $MODEL) from boards/$1"

	cat >> "$mk" <<-EOF

	define Device/$DEVICE
	  \$(Device/$SOC)
	  DEVICE_VENDOR := $VENDOR
	  DEVICE_MODEL := $MODEL
	  DEVICE_DTS := $(basename "$DTB" .dtb)
	  UBOOT_DEVICE_NAME := $UBOOT
	  DEVICE_PACKAGES := $PACKAGES
	endef
	TARGET_DEVICES += $DEVICE
	EOF

	make -C "$IB" info >/dev/null	# generates .profiles.mk
	[ -f "$IB/.profiles.mk" ] || die "no .profiles.mk in $IB"
	cat >> "$IB/.profiles.mk" <<-EOF
	PROFILE_NAMES += DEVICE_$DEVICE
	DEVICE_${DEVICE}_NAME:=$VENDOR $MODEL
	DEVICE_${DEVICE}_HAS_IMAGE_METADATA:=1
	DEVICE_${DEVICE}_SUPPORTED_DEVICES:=${DEVICE/_/,}
	DEVICE_${DEVICE}_PACKAGES:=$PACKAGES
	EOF
	touch "$IB/.profiles.mk"

	# boot loader like binman's u-boot-rockchip.bin: idbloader at sector 64,
	# u-boot.itb at sector 16384 (the image recipe writes it at sector 64)
	mkdir -p "$IB/staging_dir/image"
	tmp="$IB/staging_dir/image/$UBOOT-u-boot-rockchip.bin"
	dd if="$dir/u-boot/idbloader.img" of="$tmp" 2>/dev/null
	dd if="$dir/u-boot/u-boot.itb" of="$tmp" seek=$((16384 - 64)) conv=notrunc 2>/dev/null

	# kernel: FIT with the lzma compressed official Image + the board dtb,
	# as the rockchip image recipe builds it (kernel-bin | lzma | fit lzma)
	kdir=$(find "$IB/build_dir" -maxdepth 2 -type d -name "linux-${T}_${S}" | head -n 1)
	[ -d "$kdir" ] || die "no kernel directory in $IB/build_dir"
	kver=$(basename "$(ls -d "$kdir"/linux-[0-9]* | head -n 1)")
	kver=${kver#linux-}
	tmp=$WORK/kernel-$DEVICE
	rm -rf "$tmp"
	mkdir -p "$tmp"
	if [ -f "$kdir/Image" ]; then
		cp "$kdir/Image" "$tmp/kernel"
		"$IB/staging_dir/host/bin/lzma" e "$tmp/kernel" -lc1 -lp2 -pb2 "$tmp/kernel.lzma"
	else
		# no plain Image in this ImageBuilder: take the (lzma) kernel of
		# another device of the same SoC family
		local fit
		fit=$(ls "$kdir"/*-kernel.bin | head -n 1)
		log "no $kdir/Image, kernel from $(basename "$fit")"
		dumpimage -T flat_dt -p 0 -o "$tmp/kernel.lzma" "$fit"
	fi
	cp "$dir/$DTB" "$tmp/board.dtb"
	"$IB/scripts/mkits.sh" -D "$DEVICE" -o "$tmp/kernel.its" -k "$tmp/kernel.lzma" \
		-C lzma -d "$tmp/board.dtb" -a "$LOADADDR" -e "$LOADADDR" \
		-c config-1 -A arm64 -v "$kver"
	mkimage -f "$tmp/kernel.its" "$kdir/$DEVICE-kernel.bin" >/dev/null
	log "kernel $kver + $(basename "$DTB") -> $DEVICE-kernel.bin"
}
[ -n "$BOARD" ] && inject_board "$BOARD"

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
have() { [ ! -s "$avail" ] || grep -qx "$1" "$avail"; }

## package list
pkgs=""
for l in $LISTS; do
	while read -r p; do
		case "$p" in
			""|\#*) continue ;;
			-*) pkgs="$pkgs $p" ;;
			\?*)
				p=${p#\?}
				dep=${p#*:}
				p=${p%%:*}
				if have "$p" && { [ "$dep" = "$p" ] || have "$dep"; }; then
					pkgs="$pkgs $p"
				else
					log "optional package $p not available for $T/$S, skipped"
				fi
				;;
			*) pkgs="$pkgs $p" ;;
		esac
	done < "$IB_TOP/ib/packages/$l.list"
done

## first boot defaults: hostname / SSID, single network port = DHCP uplink,
## Docker firewall, stable MAC on added boards
FILES=$WORK/files-$VARIANT
rm -rf "$FILES"
mkdir -p "$FILES/etc/uci-defaults"
cp "$IB_TOP/files/etc/uci-defaults/96-docker-firewall" \
   "$IB_TOP/files/etc/uci-defaults/98-khadas-network" "$FILES/etc/uci-defaults/"
[ -n "$BOARD" ] && cp "$IB_TOP/files-ib/etc/uci-defaults/93-mac-from-mmc" "$FILES/etc/uci-defaults/"
cat > "$FILES/etc/uci-defaults/90-board-name" <<EOF
#!/bin/sh
# host name (router list, http://$HOST.local/) and Wi-Fi SSID of this image
[ "\$(uci -q get system.@system[0].hostname)" = OpenWrt ] && {
	uci set system.@system[0].hostname='$HOST'
	uci commit system
}
[ -f /etc/config/wifiauto ] && [ "\$(uci -q get wifiauto.main.ssid)" = Khadas-Edge ] && {
	uci set wifiauto.main.ssid='$SSID'
	uci commit wifiauto
}
exit 0
EOF
chmod +x "$FILES/etc/uci-defaults/"*

log "$VARIANT: $T/$S $PROFILE, packages:$pkgs"
BIN=$WORK/bin-$VARIANT
rm -rf "$BIN"
make -C "$IB" image PROFILE="$PROFILE" PACKAGES="$pkgs" FILES="$FILES" \
	ROOTFS_PARTSIZE="$SIZE" BIN_DIR="$BIN"

## canonical file names
rm -rf "$DEST"
mkdir -p "$DEST"
name=openwrt-$OW_VER-$VARIANT
pick() { ls "$BIN"/*"$1" 2>/dev/null | head -n 1 || true; }
cp "$(ls "$BIN"/*.manifest | head -n 1)" "$DEST/$name.manifest"

case "$VARIANT" in
	x86-64-pc)
		cp "$(pick squashfs-combined-efi.img.gz)" "$DEST/$name-efi.img.gz"
		cp "$(pick squashfs-combined.img.gz)" "$DEST/$name-bios.img.gz"
		;;
	x86-64-vm)
		# GPT image with GRUB for UEFI (OVMF) and BIOS (SeaBIOS)
		efi=$(pick squashfs-combined-efi.img.gz)
		[ -n "$efi" ] || die "no image in $BIN"
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
		img=$(pick squashfs-combined.img.gz)
		[ -n "$img" ] || img=$(pick squashfs-combined-efi.img.gz)
		cp "$img" "$DEST/$name-bios.img.gz"
		;;
	*)
		# boards: factory (first install, if the target has one) + sysupgrade
		f=$(pick squashfs-factory.img.gz)
		[ -n "$f" ] && cp "$f" "$DEST/$name-factory.img.gz"
		f=$(pick squashfs-sysupgrade.img.gz)
		[ -n "$f" ] || die "no sysupgrade image in $BIN"
		cp "$f" "$DEST/$name-sysupgrade.img.gz"
		;;
esac
[ "$(ls "$DEST"/*.img.gz "$DEST"/*.qcow2 2>/dev/null | wc -l)" -gt 0 ] || die "no image for $VARIANT"

(cd "$DEST" && sha256sum -- * > "sha256sums-$VARIANT")
log "DONE: $DEST"
ls -l "$DEST"
