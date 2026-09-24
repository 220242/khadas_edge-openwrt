# khadas edge openwrt

OpenWrt 25.12 for Khadas Edge boards https://docs.khadas.com/edge/ (RockChip RK3399):
**Edge**, **Edge-V**, **Edge-Captain**.

![khadas vims openwrt](pics/khadas_vim_openwrt.jpg)

## Change logs

+ [README.changes.md](README.changes.md)

## What's inside

Full OpenWrt source build (`rockchip/armv8` target, Linux 6.12, mainline U-Boot + TF-A),
Khadas Edge boards added as OpenWrt devices, kernel built with **KVM**.

+ **Wi-Fi 6 / 6E / 7 (AX / BE)** PCIe M.2 and USB cards
  + Intel AX200, AX210, BE200 (`iwlwifi`)
  + MediaTek MT7921 / MT7922 / MT7925 (PCIe + USB), MT7915 / MT7916, MT7996 / MT7992 (BE)
  + Realtek RTL8852AE / RTL8852BE / RTL8852CE / RTL8851BE / RTL8922AE (BE)
  + Qualcomm WCN6855 (AX, ath11k), WCN7850 (BE, ath12k)
  + onboard AP6356S (BCM4356 SDIO)
  + full `wpad-mbedtls` (hostapd + wpa_supplicant with 802.11ax / 802.11be)
  + note: Intel cards work as client only (no 5 GHz / 6 GHz access point),
    for an access point use MediaTek / Qualcomm cards
+ **4G / 5G modems** USB and M.2 PCIe (MHI): Quectel RM5xx / RG5xx, Sierra, Fibocom, Huawei ...
  + ModemManager + LuCI protocol (`Network → Interfaces → Add → ModemManager`)
  + QMI / MBIM / NCM / RNDIS / serial, `uqmi`, `umbim`, `qmicli`, `mbimcli`, `sms-tool`
+ **Virtual machines (KVM / QEMU)** - `Services → Virtual Machines`
  + arm64 guests with UEFI (Debian, Ubuntu, Alpine, OpenWrt ...), install from ISO
  + virtio disk / network (bridged to `br-lan`), VNC screen, autostart
+ **Containers**
  + Docker + docker-compose, LuCI `Docker` (luci-app-dockerman)
  + LXC, LuCI `Services → LXC Containers`
+ storage: NVMe (Edge-Captain M.2), USB, ext4 / btrfs, 2 GB root partition

## Images

GitHub Actions builds images on every push (Actions → build → artifacts) and
publishes a release for `v*` tags:

+ `openwrt-25.12.5-rockchip-armv8-khadas_edge-v-squashfs-sysupgrade.img.gz` - Edge-V
+ `openwrt-25.12.5-rockchip-armv8-khadas_edge-captain-squashfs-sysupgrade.img.gz` - Edge-Captain
+ `openwrt-25.12.5-rockchip-armv8-khadas_edge-squashfs-sysupgrade.img.gz` - Edge (module)

## Build

~2-4 hours, ~40 GB disk, Linux host with OpenWrt build dependencies
(https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem)

```
git clone https://github.com/220242/khadas_edge-openwrt.git
cd khadas_edge-openwrt

./openwrt/build.sh           # images -> out/
./openwrt/build.sh prepare   # only prepare tree in build/openwrt (then: make menuconfig)

OW_REL=v25.12.5 JOBS=8 ./openwrt/build.sh
```

+ [openwrt/patches](openwrt/patches) - Khadas Edge devices, KVM kernel config, QEMU for rockchip
+ [openwrt/diffconfig](openwrt/diffconfig) - package selection
+ [openwrt/feed/luci-app-kvm](openwrt/feed/luci-app-kvm) - VM manager (LuCI + procd)
+ [openwrt/files](openwrt/files) - rootfs overlay

## Installation

write image to SD card or eMMC

```
gzip -dc openwrt-*-khadas_edge-v-squashfs-sysupgrade.img.gz | sudo dd bs=1M of=/dev/SD_PATH
sync
```

RK3399 boots from SPI flash, then eMMC, then SD card. To boot from SD card
the bootloader in SPI flash / eMMC must be erased (or use Krescue / Oowow to
write the image directly to eMMC). See [files/docs](files/docs).

first boot: LAN `eth0` 192.168.1.1, LuCI http://192.168.1.1, user `root` without password.
Internet: 5G modem (ModemManager) or Wi-Fi client (`Network → Wireless → Scan`).

## Virtual machines quick start

```
# storage for VMs, e.g. NVMe on Edge-Captain
mkfs.ext4 /dev/nvme0n1 && mkdir -p /mnt/vm && mount /dev/nvme0n1 /mnt/vm
cd /mnt/vm && wget https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/debian-13.1.0-arm64-netinst.iso
```

`Services → Virtual Machines`: add VM, set disk `/mnt/vm/debian.qcow2`, disk size `16G`,
CD image, VNC display `0`, enable `Run`, `Save & Apply`, connect VNC client to `192.168.1.1:5900`.

RK3399 is big.LITTLE (4x Cortex-A53 + 2x Cortex-A72): KVM vCPUs are pinned to one
core type with `CPU affinity` (default `4-5`, A72).

## Legacy build

`scripts/build` - old repack build (Khadas 5.14 kernel + OpenWrt armsr userspace),
no AX / BE Wi-Fi drivers and no KVM in that kernel.

## related projects

+ https://github.com/hyphop/khadas-openwrt (upstream, VIMs + Edge)
+ https://github.com/openwrt/openwrt

## links

+ https://openwrt.org/
+ https://docs.khadas.com/edge/
+ https://github.com/khadas
