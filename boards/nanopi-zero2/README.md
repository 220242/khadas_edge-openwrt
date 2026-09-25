# FriendlyElec NanoPi Zero2: board files

OpenWrt 25.12.5 has no NanoPi Zero2 (RockChip RK3528) device yet, but its 6.12
kernel carries the RK3528 support up to Linux 6.19. The image
(`openwrt/ib/imagebuilder.sh nanopi-zero2`) uses the **official** rockchip/armv8
kernel and kmods and adds the device from these files (`board.conf`).

| path | what | origin |
|---|---|---|
| `dts/rk3528-nanopi-zero2.dts` | device tree source | Linux v6.18 (`arch/arm64/boot/dts/rockchip`), GPL-2.0+ OR MIT |
| `dtb/rk3528-nanopi-zero2.dtb` | compiled with the OpenWrt 25.12.5 kernel tree (6.12.94 + patches) | |
| `dtb/rk3528-nanopi-zero2.decompiled.dts` | the dtb decompiled | `dtc -I dtb -O dts` |
| `u-boot/idbloader.img`, `u-boot/u-boot.itb` | U-Boot `generic-rk3528` (boots any RK3528 from SD / eMMC) | U-Boot v2025.10 + OpenWrt patches, Rockchip `rk3528_ddr_1056MHz_v1.11.bin` + `rk3528_bl31_v1.20.elf` (rkbin 74213af1, as OpenWrt) |
| `u-boot/generic-rk3528.config` | U-Boot configuration | |

**Not tested on the board yet.** U-Boot is the generic RK3528 one (no board
specific U-Boot in v2025.10): SD card / eMMC, no network in the boot loader.

Hardware: RK3528A (4x Cortex-A53), LPDDR4, eMMC (optional) + microSD,
1 GbE (RTL8211F on GMAC1), USB. One network port: the image makes it the DHCP
uplink (see the main README).

Writing only the boot loader: `dd if=u-boot/idbloader.img of=/dev/sdX seek=64`,
`dd if=u-boot/u-boot.itb of=/dev/sdX seek=16384` (`conv=notrunc,fsync`).
