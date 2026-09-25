# shellcheck shell=bash
# helpers for the official OpenWrt SDK / ImageBuilder (sourced)

OW_VER=${OW_VER:-25.12.5}
OW_MIRROR=${OW_MIRROR:-https://downloads.openwrt.org}
IB_TOP=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)	# openwrt/
IB_ROOT=$(cd "$IB_TOP/.." && pwd)
WORK=${WORK:-$IB_ROOT/build/ib}
DL=${DL:-$WORK/dl}

log() { echo "[i] $*" >&2; }
die() { echo "[e] $*" >&2; exit 1; }

# fetch_tool imagebuilder|sdk TARGET SUBTARGET DIR
#   download (sha256 checked, cached in $DL) and unpack the official tool
fetch_tool() {
	local kind="$1" target="$2" sub="$3" dir="$4"
	local base="$OW_MIRROR/releases/$OW_VER/targets/$target/$sub"
	local line sum file

	mkdir -p "$DL"
	curl -fsSL --retry 3 "$base/sha256sums" -o "$DL/sha256sums-$target-$sub" ||
		die "no release $OW_VER for $target/$sub ($base)"
	line=$(grep -E "[ *]openwrt-$kind-[^ ]*\.tar\.(zst|xz)$" "$DL/sha256sums-$target-$sub" | head -n 1)
	[ -n "$line" ] || die "no $kind in $base/sha256sums"
	sum=${line%% *}
	file=${line##*[ *]}
	if [ "$(cat "$dir/.khadas-$kind" 2>/dev/null)" = "$file" ]; then
		log "$kind $target/$sub: $dir (unpacked)"
		return 0
	fi
	if ! echo "$sum  $DL/$file" | sha256sum -c --status 2>/dev/null; then
		log "download $file"
		curl -fL --retry 3 --retry-delay 5 "$base/$file" -o "$DL/$file.part"
		mv "$DL/$file.part" "$DL/$file"
		echo "$sum  $DL/$file" | sha256sum -c --quiet || die "sha256 mismatch: $file"
	fi
	rm -rf "$dir"
	mkdir -p "$dir"
	log "unpack $file"
	tar -xf "$DL/$file" --strip-components=1 -C "$dir"
	echo "$file" > "$dir/.khadas-$kind"
}

# feeds.conf with GitHub mirrors (git.openwrt.org is slow / often blocked)
github_feeds() {
	sed -e 's#https://git.openwrt.org/feed/packages.git#https://github.com/openwrt/packages.git#' \
	    -e 's#https://git.openwrt.org/project/luci.git#https://github.com/openwrt/luci.git#' \
	    -e 's#https://git.openwrt.org/feed/routing.git#https://github.com/openwrt/routing.git#' \
	    -e 's#https://git.openwrt.org/feed/telephony.git#https://github.com/openwrt/telephony.git#' \
	    -e 's#https://git.openwrt.org/openwrt/openwrt.git#https://github.com/openwrt/openwrt.git#' \
	    "$1"
}

# Edge-V kernels built from source (openwrt/build.sh), published by the CI
# in $KERNELS_REPO: release kernel-<release>-<variant>-<key> with the
# ImageBuilder, the apk repository is branch apk-<release>-<variant>-<key>
KERNELS_REPO=${KERNELS_REPO:-220242/khadas-kernels}
kernel_tag() {
	echo "kernel-$OW_VER-$1-$(OW_REL="v$OW_VER" "$IB_TOP/kernel-key.sh" "$1")"
}
kernel_apk_repo() {
	echo "https://raw.githubusercontent.com/$KERNELS_REPO/apk-${1#kernel-}"
}

# fetch_kernel_ib VARIANT DIR: download (sha256 checked, cached) and unpack
# the ImageBuilder of the source built kernel
fetch_kernel_ib() {
	local variant="$1" dir="$2" tag base sum
	tag=$(kernel_tag "$variant")
	base=https://github.com/$KERNELS_REPO/releases/download/$tag
	if [ "$(cat "$dir/.khadas-kernel" 2>/dev/null)" = "$tag" ]; then
		log "ImageBuilder $tag: $dir (unpacked)"
		return 0
	fi
	mkdir -p "$DL"
	curl -fsSL --retry 3 "$base/sha256sums" -o "$DL/sha256sums-$tag" ||
		die "no kernel $tag in $KERNELS_REPO (the kernel job builds it)"
	sum=$(awk '$2 ~ /imagebuilder\.tar\.zst$/ { print $1 }' "$DL/sha256sums-$tag")
	[ -n "$sum" ] || die "no imagebuilder.tar.zst in $base/sha256sums"
	if ! echo "$sum  $DL/$tag.tar.zst" | sha256sum -c --status 2>/dev/null; then
		log "download $tag ImageBuilder"
		curl -fL --retry 3 --retry-delay 5 "$base/imagebuilder.tar.zst" -o "$DL/$tag.tar.zst.part"
		mv "$DL/$tag.tar.zst.part" "$DL/$tag.tar.zst"
		echo "$sum  $DL/$tag.tar.zst" | sha256sum -c --quiet || die "sha256 mismatch: $tag"
	fi
	rm -rf "$dir"
	mkdir -p "$dir"
	log "unpack $tag ImageBuilder"
	tar -xf "$DL/$tag.tar.zst" --strip-components=1 -C "$dir"
	echo "$tag" > "$dir/.khadas-kernel"
}
