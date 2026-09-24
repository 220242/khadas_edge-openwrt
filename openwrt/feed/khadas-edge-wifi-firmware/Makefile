#
# Wi-Fi firmware + NVRAM for the onboard AP6356S (BCM4356 rev A2)
# of Khadas Edge / Edge-V / Edge-Captain, as used by Khadas (fenix).
#
# OpenWrt cypress-firmware-4356-sdio is built for BCM4356 rev A3
# (4356a3-roml) and ships a clm_blob that the A2 firmware can not load,
# brcmfmac treats a failed clm_blob download as fatal.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=khadas-edge-wifi-firmware
PKG_VERSION:=2026.06.23
PKG_RELEASE:=1

PKG_LICENSE:=Broadcom-proprietary
PKG_MAINTAINER:=Khadas Edge OpenWrt

include $(INCLUDE_DIR)/package.mk

FENIX_COMMIT:=1eded14ff94001cee8b6350adff1dc03292f2743
FENIX_URL:=https://raw.githubusercontent.com/khadas/fenix/$(FENIX_COMMIT)/archives/hwpacks/wlan-firmware/brcm

define Download/khadas-4356-firmware
  URL:=$(FENIX_URL)
  URL_FILE:=brcmfmac4356-sdio.bin
  FILE:=khadas-fenix-$(FENIX_COMMIT)-brcmfmac4356-sdio.bin
  HASH:=42e603aacc1c25b9f797cab44a192a647f9a5527871954d2eb910f508edbd8c7
endef
$(eval $(call Download,khadas-4356-firmware))

define Download/khadas-4356-nvram
  URL:=$(FENIX_URL)
  URL_FILE:=brcmfmac4356-sdio.txt
  FILE:=khadas-fenix-$(FENIX_COMMIT)-brcmfmac4356-sdio.txt
  HASH:=205af14e8e98acc858d729e3a8161c035fee2c186146a42d58bb0137b9c3c360
endef
$(eval $(call Download,khadas-4356-nvram))

define Package/khadas-edge-wifi-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=Khadas Edge AP6356S (BCM4356A2) Wi-Fi firmware and NVRAM
  URL:=https://github.com/khadas/fenix
  CONFLICTS:=cypress-firmware-4356-sdio brcmfmac-nvram-4356-sdio
  PKGARCH:=all
endef

define Package/khadas-edge-wifi-firmware/description
 Firmware 7.35.184.0 (4356a2-roml) and NVRAM used by Khadas for the
 onboard AP6356S module. Installed with board specific names
 (loaded first by brcmfmac) and generic names, without clm_blob.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(DL_DIR)/khadas-fenix-$(FENIX_COMMIT)-brcmfmac4356-sdio.bin $(PKG_BUILD_DIR)/brcmfmac4356-sdio.bin
	$(CP) $(DL_DIR)/khadas-fenix-$(FENIX_COMMIT)-brcmfmac4356-sdio.txt $(PKG_BUILD_DIR)/brcmfmac4356-sdio.txt
endef

define Build/Compile
endef

define Package/khadas-edge-wifi-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/brcm
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/brcmfmac4356-sdio.bin $(1)/lib/firmware/brcm/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/brcmfmac4356-sdio.txt $(1)/lib/firmware/brcm/
	$(LN) brcmfmac4356-sdio.bin $(1)/lib/firmware/brcm/brcmfmac4356-sdio.khadas,edge.bin
	$(LN) brcmfmac4356-sdio.txt $(1)/lib/firmware/brcm/brcmfmac4356-sdio.khadas,edge.txt
	$(LN) brcmfmac4356-sdio.bin $(1)/lib/firmware/brcm/brcmfmac4356-sdio.khadas,edge-v.bin
	$(LN) brcmfmac4356-sdio.txt $(1)/lib/firmware/brcm/brcmfmac4356-sdio.khadas,edge-v.txt
	$(LN) brcmfmac4356-sdio.bin $(1)/lib/firmware/brcm/brcmfmac4356-sdio.khadas,edge-captain.bin
	$(LN) brcmfmac4356-sdio.txt $(1)/lib/firmware/brcm/brcmfmac4356-sdio.khadas,edge-captain.txt
endef

$(eval $(call BuildPackage,khadas-edge-wifi-firmware))
