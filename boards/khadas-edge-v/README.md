# Khadas Edge-V: board files

Everything this project uses that is specific to the Khadas Edge-V (RockChip RK3399,
VIM form factor), collected in one place. The OpenWrt build itself takes these
from the patches / feed in [openwrt/](../../openwrt); the copies here are for
reference, other distributions and manual recovery.

| path | what | origin |
|---|---|---|
| `dts/rk3399-khadas-edge-v.dts`, `dts/rk3399-khadas-edge.dtsi` | device tree sources | Linux 6.12.94 (`arch/arm64/boot/dts/rockchip`), GPL-2.0+ OR MIT |
| `dtb/rk3399-khadas-edge-v.dtb` | compiled device tree, as in the OpenWrt kernel | Linux 6.12.94 + OpenWrt 25.12.5 patches |
| `dtb/rk3399-khadas-edge-v.decompiled.dts` | the dtb decompiled (all includes resolved) | `dtc -I dtb -O dts` |
| `u-boot/idbloader.img` | TPL + SPL (DRAM init, open source LPDDR4 init) | U-Boot v2025.10 + OpenWrt patches |
| `u-boot/u-boot.itb` | U-Boot + TF-A BL31, with **HDMI** output | U-Boot v2025.10 + OpenWrt patches + `301-…HDMI.patch`, TF-A v2.13 |
| `u-boot/301-khadas-edge-v-enable-HDMI.patch` | U-Boot defconfig change: video on HDMI | this project |
| `u-boot/khadas-edge-v-rk3399.config` | full U-Boot configuration used | |
| `boot/boot.cmd`, `boot/boot.scr` | OpenWrt boot script (console on HDMI + serial) | this project, `mkimage -T script` |
| `wifi/brcmfmac4356-sdio.bin`, `wifi/brcmfmac4356-sdio.txt` | AP6356S firmware (BCM4356A2, 7.35.184) + Khadas NVRAM | [khadas/fenix](https://github.com/khadas/fenix/tree/1eded14ff94001cee8b6350adff1dc03292f2743/archives/hwpacks/wlan-firmware/brcm), Broadcom firmware license |
| `openwrt/armv8.mk.device` | OpenWrt device definition | this project |
| `openwrt/uboot-rockchip.mk` | OpenWrt U-Boot package entry | this project |
| `openwrt/02_network.snippet` | MAC address from the eMMC CID | this project |
| `openwrt/kernel.config` | kernel options added to the OpenWrt kernel | this project |

## Hardware notes

+ SoC RK3399: 2x Cortex-A72 + 4x Cortex-A53, Mali-T860, LPDDR4
+ storage: eMMC (`mmc2`, Linux `mmcblk2`), SD card (`mmc1`, `mmcblk1`),
  SPI NOR flash W25Q128FW 16 MB (`spi1`), PCIe (enabled in the Edge-V device tree)
+ Wi-Fi / BT: AP6356S (BCM4356A2, SDIO `mmc0`), 2x2 802.11ac + BT 4.1
+ Ethernet: RK3399 GMAC, RGMII PHY, one port
+ HDMI 2.0 (VOP big/little + Synopsys DW HDMI), PWM fan, IR receiver,
  keys: power (GPIO), recovery (ADC), LEDs `sys_led`, `user_led`
+ serial console: UART2, `ttyS2`, **1500000** 8N1, 3.3 V

## Boot flow

1. The RK3399 boot ROM looks for a boot loader in **SPI flash → eMMC → SD card**
   (`idbloader.img` at sector 64). The first one found wins: with the factory
   Android / Ubuntu on the eMMC an SD card is ignored.
2. `idbloader.img`: TPL initialises LPDDR4, SPL loads `u-boot.itb`
   (sector 16384 = 8 MiB) with TF-A BL31.
3. U-Boot (logo + messages on HDMI) runs `boot.scr` from partition 1:
   loads `kernel.img` (FIT: kernel + `rk3399-khadas-edge-v.dtb`), root is
   partition 2 by PARTUUID.

## Writing only the boot loader

To an SD card / eMMC that already has partitions starting at 16 MiB or later
(OpenWrt images do):

```
sudo dd if=u-boot/idbloader.img of=/dev/sdX seek=64 conv=notrunc,fsync
sudo dd if=u-boot/u-boot.itb of=/dev/sdX seek=16384 conv=notrunc,fsync
```

On the board, from OpenWrt (eMMC = `/dev/mmcblk2`):

```
dd if=idbloader.img of=/dev/mmcblk2 seek=64 conv=notrunc,fsync
dd if=u-boot.itb of=/dev/mmcblk2 seek=16384 conv=notrunc,fsync
```

Keep a working SD card at hand: a broken boot loader on the eMMC is recovered
by booting from the SD card (or with Krescue / the Rockchip USB maskrom tools).
The U-Boot environment is on the boot device at offset `0x3F8000`.

## Rebuilding

+ U-Boot: `git clone -b v2025.10 https://github.com/u-boot/u-boot`, apply
  `package/boot/uboot-rockchip/patches/*` of OpenWrt 25.12.5 and
  `u-boot/301-khadas-edge-v-enable-HDMI.patch`, then
  `make khadas-edge-v-rk3399_defconfig && make CROSS_COMPILE=aarch64-linux-gnu- BL31=…/bl31.elf`
  (TF-A: `make PLAT=rk3399 CROSS_COMPILE=aarch64-linux-gnu- M0_CROSS_COMPILE=arm-none-eabi- bl31`)
+ dtb: from a Linux 6.12 tree `make ARCH=arm64 rockchip/rk3399-khadas-edge-v.dtb`
+ boot script: `mkimage -A arm64 -O linux -T script -C none -d boot/boot.cmd boot/boot.scr`
