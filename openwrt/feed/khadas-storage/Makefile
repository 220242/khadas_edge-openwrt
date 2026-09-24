#
# Install to USB / NVMe / eMMC, boot from external disk, expand root filesystem
#

include $(TOPDIR)/rules.mk

PKG_NAME:=khadas-storage
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/khadas-storage
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Khadas Edge install to disk / expand root filesystem
  DEPENDS:=@TARGET_rockchip +sfdisk +partx-utils +losetup +f2fsck +resize2fs +e2fsprogs +fwtool
endef

define Package/khadas-storage/description
 - install OpenWrt (copy of the running system or an uploaded image)
   to a USB SSD, NVMe, eMMC or SD card
 - boot from NVMe / USB disk: U-Boot script on eMMC / SD prefers an
   OpenWrt disk on NVMe or USB
 - expand the root partition and overlay filesystem to the whole disk
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files/usr/share/khadas-storage/boot-external.txt $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(STAGING_DIR_HOST)/bin/mkimage -A arm -O linux -T script -C none -a 0 -e 0 \
		-n "Khadas Edge OpenWrt" \
		-d $(PKG_BUILD_DIR)/boot-external.txt $(PKG_BUILD_DIR)/boot-external.scr
endef

define Package/khadas-storage/install
	$(INSTALL_DIR) $(1)/usr/libexec $(1)/lib/preinit $(1)/usr/share/khadas-storage
	$(INSTALL_BIN) ./files/usr/libexec/khadas-storage $(1)/usr/libexec/
	$(INSTALL_DATA) ./files/lib/preinit/79_expand_rootfs $(1)/lib/preinit/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/boot-external.scr $(1)/usr/share/khadas-storage/
endef

$(eval $(call BuildPackage,khadas-storage))
