#
# LuCI app for KVM / QEMU virtual machines (Khadas Edge, RK3399)
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for KVM/QEMU virtual machines
LUCI_DESCRIPTION:=Create, start and stop QEMU/KVM virtual machines from LuCI
LUCI_DEPENDS:=+luci-base +qemu-aarch64-softmmu +qemu-img +kmod-tun +kmod-vhost-net +taskset
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Khadas Edge OpenWrt

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
