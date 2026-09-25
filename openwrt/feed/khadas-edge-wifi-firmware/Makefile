#
# Wi-Fi firmware + NVRAM for the onboard module of Khadas Edge / Edge-V /
# Edge-Captain, as used by Khadas (fenix):
#   AP6398S (Broadcom BCM4359 rev C0) - fenix: "AP6398S only on Edge,
#     VIM2 V14 and VIM3"
#   AP6356S (Broadcom BCM4356 rev A2) - named in the Linux device tree,
#     early boards
# Both are installed, brcmfmac picks the firmware by the chip ID:
# brcmfmac43xx-sdio.<board compatible>.bin / .txt, then the generic name.
# OpenWrt has no firmware for AP6398S; its cypress-firmware-4356-sdio is
# built for BCM4356 rev A3 and ships a clm_blob the A2 firmware rejects.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=khadas-edge-wifi-firmware
PKG_VERSION:=2026.06.23
PKG_RELEASE:=2

PKG_LICENSE:=Broadcom-proprietary
PKG_MAINTAINER:=Khadas Edge OpenWrt

include $(INCLUDE_DIR)/package.mk

FENIX_COMMIT:=1eded14ff94001cee8b6350adff1dc03292f2743
FENIX_URL:=https://raw.githubusercontent.com/khadas/fenix/$(FENIX_COMMIT)/archives/hwpacks/wlan-firmware/brcm

define Download/khadas-ap6398s-firmware
  URL:=$(FENIX_URL)
  URL_FILE:=brcmfmac4359-sdio_ap6398s.bin
  FILE:=khadas-fenix-$(FENIX_COMMIT)-brcmfmac4359-sdio_ap6398s.bin
  HASH:=97b66c8100ad0ad1ec8d0b43f8839dfd8d7776e73f2e87ee9e40078fe3001207
endef
$(eval $(call Download,khadas-ap6398s-firmware))

define Download/khadas-ap6398s-nvram
  URL:=$(FENIX_URL)
  URL_FILE:=brcmfmac4359-sdio_ap6398s.txt
  FILE:=khadas-fenix-$(FENIX_COMMIT)-brcmfmac4359-sdio_ap6398s.txt
  HASH:=ad8f02115f8c0f595a3bea9777a23601a041a1d2f343b579b01a9f5b08f0efa3
endef
$(eval $(call Download,khadas-ap6398s-nvram))

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
  TITLE:=Khadas Edge AP6398S / AP6356S Wi-Fi firmware and NVRAM
  URL:=https://github.com/khadas/fenix
  CONFLICTS:=cypress-firmware-4356-sdio brcmfmac-nvram-4356-sdio
  PKGARCH:=all
endef

define Package/khadas-edge-wifi-firmware/description
 Firmware + NVRAM used by Khadas for the onboard module: AP6398S
 (BCM4359C0, 9.87.51.11.82) and AP6356S (BCM4356A2, 7.35.184.0), with
 board specific names (loaded first by brcmfmac) and generic names.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(DL_DIR)/khadas-fenix-$(FENIX_COMMIT)-brcmfmac4359-sdio_ap6398s.bin $(PKG_BUILD_DIR)/brcmfmac4359-sdio.bin
	$(CP) $(DL_DIR)/khadas-fenix-$(FENIX_COMMIT)-brcmfmac4359-sdio_ap6398s.txt $(PKG_BUILD_DIR)/brcmfmac4359-sdio.txt
	$(CP) $(DL_DIR)/khadas-fenix-$(FENIX_COMMIT)-brcmfmac4356-sdio.bin $(PKG_BUILD_DIR)/brcmfmac4356-sdio.bin
	$(CP) $(DL_DIR)/khadas-fenix-$(FENIX_COMMIT)-brcmfmac4356-sdio.txt $(PKG_BUILD_DIR)/brcmfmac4356-sdio.txt
endef

define Build/Compile
endef

define Package/khadas-edge-wifi-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/brcm
	for c in 4359 4356; do \
		$(INSTALL_DATA) $(PKG_BUILD_DIR)/brcmfmac$$$$c-sdio.bin $(1)/lib/firmware/brcm/; \
		$(INSTALL_DATA) $(PKG_BUILD_DIR)/brcmfmac$$$$c-sdio.txt $(1)/lib/firmware/brcm/; \
		for b in edge edge-v edge-captain; do \
			$(LN) brcmfmac$$$$c-sdio.bin $(1)/lib/firmware/brcm/brcmfmac$$$$c-sdio.khadas,$$$$b.bin; \
			$(LN) brcmfmac$$$$c-sdio.txt $(1)/lib/firmware/brcm/brcmfmac$$$$c-sdio.khadas,$$$$b.txt; \
		done; \
	done
endef

$(eval $(call BuildPackage,khadas-edge-wifi-firmware))
