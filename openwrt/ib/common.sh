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
