#!/bin/sh

# hyphop #

#= opkg.conf template (OpenWrt 23.05 / 24.10 only, 25.x+ uses apk)

[ "$OW_DL" ] || {
    PR=$(dirname $0)
    echo "[i] autoconf from $PR/build.conf">&2
    . $PR/build.conf
}

#
# opkg config template
#

cat <<end

src/gz openwrt_core $OW_DL/$REL/targets/$TARGET/$SUBTARGET/packages
src/gz openwrt_base $OW_DL/$REL/packages/$OWARCH/base
src/gz openwrt_luci $OW_DL/$REL/packages/$OWARCH/luci
src/gz openwrt_packages $OW_DL/$REL/packages/$OWARCH/packages
src/gz openwrt_routing $OW_DL/$REL/packages/$OWARCH/routing
src/gz openwrt_telephony $OW_DL/$REL/packages/$OWARCH/telephony

arch all 100
arch $OWARCH 200

dest root $OWTMP
dest ram /tmp

lists_dir ext $OPKG_LIST

#option overlay_root ../tmp/overlay
#option check_signature

end
