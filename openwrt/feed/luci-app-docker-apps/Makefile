#
# LuCI: one click Docker apps (catalog, Docker Hub search, compose URL)
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=One click Docker apps
LUCI_DESCRIPTION:=Install Docker apps from a catalog, Docker Hub search, any registry image or a docker-compose file
LUCI_DEPENDS:=+luci-base +dockerd +docker +docker-compose +curl +ca-bundle +jsonfilter
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Khadas Edge OpenWrt

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
