#
# LuCI: install to USB / NVMe / eMMC, boot from external disk, expand root
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Khadas Edge storage: install to disk, expand root filesystem
LUCI_DEPENDS:=+luci-base +khadas-storage
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Khadas Edge OpenWrt

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
