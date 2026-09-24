#
# ZeroTier internet gateway (exit node) + optional own network controller
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=ZeroTier internet gateway
LUCI_DESCRIPTION:=Share the internet connection with ZeroTier clients (exit node), \
	join a network from my.zerotier.com or run an own ZeroTier network controller
LUCI_DEPENDS:=+luci-base +zerotier +jsonfilter +uclient-fetch
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Khadas Edge OpenWrt

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
