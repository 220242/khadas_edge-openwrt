#
# LuCI: firmware update from the GitHub releases of this project
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Firmware update from the project releases
LUCI_DESCRIPTION:=Check the GitHub releases for a newer image of this device, download it, verify the SHA256 and flash it with sysupgrade
LUCI_DEPENDS:=+luci-base +curl +ca-bundle +jsonfilter
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Khadas Edge OpenWrt

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
