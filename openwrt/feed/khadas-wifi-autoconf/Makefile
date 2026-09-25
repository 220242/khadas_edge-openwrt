#
# Automatic Wi-Fi access point setup for onboard and plug-in cards
#

include $(TOPDIR)/rules.mk

PKG_NAME:=khadas-wifi-autoconf
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/khadas-wifi-autoconf
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Automatic Wi-Fi access point setup
  DEPENDS:=+ucode +ucode-mod-nl80211 +ucode-mod-uci +ucode-mod-fs +iw +wifi-scripts
  PKGARCH:=all
endef

define Package/khadas-wifi-autoconf/description
 Configures every detected Wi-Fi radio (onboard AP6398S and PCIe / USB
 cards: Intel AX200/AX210/BE200, MediaTek, Realtek, Qualcomm) as an
 access point with a band, channel and HT mode that the driver can
 really use for AP (no-IR / radar channels are skipped, Intel cards
 use 2.4 GHz), config: /etc/config/wifiauto
endef

define Package/khadas-wifi-autoconf/conffiles
/etc/config/wifiauto
endef

define Build/Compile
endef

define Package/khadas-wifi-autoconf/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,khadas-wifi-autoconf))
