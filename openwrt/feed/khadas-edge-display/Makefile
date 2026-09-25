#
# HDMI console for Khadas Edge-V (RK3399): Rockchip DRM (VOP + Synopsys
# DW HDMI) with the framebuffer console, a login on HDMI (tty1) for a USB
# keyboard and the device addresses printed on the screen.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=khadas-edge-display
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=Khadas Edge OpenWrt

include $(INCLUDE_DIR)/package.mk

define KernelPackage/drm-rockchip
  SUBMENU:=Video Support
  TITLE:=Rockchip DRM (VOP + DW HDMI) with framebuffer console
  DEPENDS:=@TARGET_rockchip @DISPLAY_SUPPORT +kmod-drm +kmod-drm-kms-helper \
	+kmod-drm-display-helper +kmod-drm-dma-helper
  KCONFIG:= \
	CONFIG_DRM_ROCKCHIP \
	CONFIG_ROCKCHIP_VOP=y \
	CONFIG_ROCKCHIP_VOP2=n \
	CONFIG_ROCKCHIP_DW_HDMI=y \
	CONFIG_ROCKCHIP_ANALOGIX_DP=n \
	CONFIG_ROCKCHIP_CDN_DP=n \
	CONFIG_ROCKCHIP_DW_MIPI_DSI=n \
	CONFIG_ROCKCHIP_INNO_HDMI=n \
	CONFIG_ROCKCHIP_LVDS=n \
	CONFIG_ROCKCHIP_RGB=n \
	CONFIG_ROCKCHIP_RK3066_HDMI=n \
	CONFIG_DRM_DW_HDMI \
	CONFIG_DRM_DW_HDMI_AHB_AUDIO=n \
	CONFIG_DRM_DW_HDMI_GP_AUDIO=n \
	CONFIG_DRM_DW_HDMI_I2S_AUDIO=n \
	CONFIG_DRM_DW_HDMI_CEC=n \
	CONFIG_DRM_FBDEV_EMULATION=y \
	CONFIG_DRM_FBDEV_OVERALLOC=100 \
	CONFIG_DRM_FBDEV_LEAK_PHYS_SMEM=n
  FILES:= \
	$(LINUX_DIR)/drivers/gpu/drm/bridge/synopsys/dw-hdmi.ko \
	$(LINUX_DIR)/drivers/gpu/drm/rockchip/rockchipdrm.ko
  AUTOLOAD:=$(call AutoProbe,dw-hdmi rockchipdrm)
endef

define KernelPackage/drm-rockchip/description
  Kernel modesetting for the Rockchip VOP with the Synopsys DesignWare
  HDMI transmitter (RK3288 / RK3328 / RK3399), fbdev emulation for the
  framebuffer console.
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

define Build/Compile
endef

define Package/khadas-edge-console/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults $(1)/etc/hotplug.d/iface $(1)/usr/libexec
	$(INSTALL_BIN) ./files/khadas-console.uci-defaults $(1)/etc/uci-defaults/96-khadas-console
	$(INSTALL_DATA) ./files/khadas-console.hotplug $(1)/etc/hotplug.d/iface/99-khadas-console
	$(INSTALL_BIN) ./files/khadas-console-info $(1)/usr/libexec/khadas-console-info
endef

$(eval $(call KernelPackage,drm-rockchip))
$(eval $(call BuildPackage,khadas-edge-console))
