#
# HDMI console for Khadas Edge-V on the official OpenWrt rockchip kernel
# (edge-v-official). The official kernel has DRM, the KMS / GEM DMA helpers
# and fbdev emulation (official kmods), but no Rockchip display driver: the
# Rockchip DRM (VOP + Synopsys DW HDMI) is built here as external modules
# from the sources of the same kernel release, with the official SDK
# (openwrt/ib/sdk-board.sh). Same package names as
# openwrt/feed/khadas-edge-display (source build); only that SDK sees this
# feed.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=khadas-edge-hdmi
PKG_RELEASE:=1

PKG_SOURCE:=$(LINUX_SOURCE)
PKG_SOURCE_URL:=$(LINUX_SITE)
PKG_HASH:=$(LINUX_KERNEL_HASH)

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=Khadas Edge OpenWrt

include $(INCLUDE_DIR)/package.mk

DRM_DIRS:=drivers/gpu/drm/rockchip drivers/gpu/drm/bridge/synopsys \
	drivers/gpu/drm/display

define KernelPackage/drm-rockchip
  SUBMENU:=Video Support
  TITLE:=Rockchip DRM (VOP + DW HDMI) for the official kernel
  DEPENDS:=@TARGET_rockchip @DISPLAY_SUPPORT +kmod-drm +kmod-drm-kms-helper \
	+kmod-drm-dma-helper
  FILES:= \
	$(PKG_BUILD_DIR)/dw-hdmi.ko \
	$(PKG_BUILD_DIR)/rockchipdrm.ko
  AUTOLOAD:=$(call AutoProbe,dw-hdmi rockchipdrm)
endef

define KernelPackage/drm-rockchip/description
  Kernel modesetting for the Rockchip VOP with the Synopsys DesignWare
  HDMI transmitter (RK3399), built from the kernel sources as external
  modules; the framebuffer console comes from the official fbdev
  emulation.
endef

define Package/khadas-edge-console
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=HDMI console for Khadas Edge-V
  DEPENDS:=@TARGET_rockchip +kmod-drm-rockchip +kmod-usb-hid
  PKGARCH:=all
endef

define Package/khadas-edge-console/description
  Login on the HDMI screen (tty1, USB keyboard) and the addresses of the
  device (web interface URL) printed on the screen when a network
  interface comes up.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	xzcat $(DL_DIR)/$(PKG_SOURCE) | $(TAR) -C $(PKG_BUILD_DIR) \
		--strip-components=1 -xf - \
		$(addprefix linux-$(LINUX_VERSION)/,$(DRM_DIRS))
	$(CP) ./Kbuild $(PKG_BUILD_DIR)/
endef

define Build/Compile
	+$(KERNEL_MAKE) M=$(PKG_BUILD_DIR) modules
endef

define Package/khadas-edge-console/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults $(1)/etc/hotplug.d/iface $(1)/usr/libexec
	$(INSTALL_BIN) ./files/khadas-console.uci-defaults $(1)/etc/uci-defaults/96-khadas-console
	$(INSTALL_DATA) ./files/khadas-console.hotplug $(1)/etc/hotplug.d/iface/99-khadas-console
	$(INSTALL_BIN) ./files/khadas-console-info $(1)/usr/libexec/khadas-console-info
endef

$(eval $(call KernelPackage,drm-rockchip))
$(eval $(call BuildPackage,khadas-edge-console))
