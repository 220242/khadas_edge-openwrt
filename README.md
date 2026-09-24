# khadas edge openwrt

OpenWrt 25.12 for Khadas Edge boards https://docs.khadas.com/edge/ (RockChip RK3399):
**Edge**, **Edge-V**, **Edge-Captain**.

![khadas vims openwrt](pics/khadas_vim_openwrt.jpg)

## Change logs

+ [README.changes.md](README.changes.md)

## What's inside

Full OpenWrt source build (`rockchip/armv8` target, Linux 6.12, mainline U-Boot + TF-A),
Khadas Edge boards added as OpenWrt devices, kernel built with **KVM**.

+ **Onboard Wi-Fi works out of the box**: AP6356S (BCM4356A2) with the Khadas firmware + NVRAM,
  access point `Khadas-Edge` / password `khadasedge` (WPA2, 2.4 GHz channel 6) in the LAN bridge
+ **Wi-Fi 6 / 6E / 7 (AX / BE)** PCIe M.2 and USB cards, each card gets an access point automatically
  + Intel AX200, AX210, BE200 (`iwlwifi`) - access point on 2.4 GHz (Intel firmware blocks AP on 5 / 6 GHz)
  + MediaTek MT7921 / MT7922 / MT7925 (PCIe + USB), MT7915 / MT7916, MT7996 / MT7992 (BE)
  + Realtek RTL8852AE / RTL8852BE / RTL8852CE / RTL8851BE / RTL8922AE (BE)
  + Qualcomm WCN6855 (AX, ath11k), WCN7850 (BE, ath12k)
  + full `wpad-mbedtls` (hostapd + wpa_supplicant with 802.11ax / 802.11be)
  + see [Wi-Fi](#wi-fi)
+ **4G / 5G modems** USB and M.2 PCIe (MHI): Quectel RM5xx / RG5xx, Sierra, Fibocom, Huawei ...
  + ModemManager + LuCI protocol (`Network → Interfaces → Add → ModemManager`)
  + QMI / MBIM / NCM / RNDIS / serial, `uqmi`, `umbim`, `qmicli`, `mbimcli`, `sms-tool`
+ **ZeroTier internet gateway** - `Services → ZeroTier Gateway`: ZeroTier clients get
  internet access through this device (exit node), see [ZeroTier gateway](#zerotier-gateway)
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
+ [openwrt/feed](openwrt/feed) - own packages:
  `luci-app-kvm` (VM manager), `luci-app-zt-gateway` (ZeroTier gateway),
  `khadas-wifi-autoconf` (Wi-Fi AP setup), `khadas-edge-wifi-firmware` (AP6356S firmware)
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

first boot: LAN `eth0` + Wi-Fi `Khadas-Edge` (password `khadasedge`) 192.168.1.1,
LuCI http://192.168.1.1, user `root` without password - set one.
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

## Wi-Fi

`khadas-wifi-autoconf` configures every new radio once (first boot, and when a USB / PCIe card
appears), settings in `/etc/config/wifiauto`:

| option | default | |
|---|---|---|
| `ssid` | `Khadas-Edge` | onboard radio, other cards get `-2G` / `-5G` suffix |
| `key` | `khadasedge` | WPA2 password, **change it** |
| `country` | `RU` | regulatory country, needed for 5 GHz |
| `band` | `auto` | `auto`: 5 GHz when the card can start an AP there, else 2.4 GHz; `2g`; `5g` |
| `enable_ap` | `1` | `0`: configure radios, but leave the access points disabled |

The band / channel / HT mode are taken from what the driver reports for AP mode: channels
marked no-IR / radar / disabled are skipped, cards without AP support are left unchanged.
Onboard AP6356S uses 2.4 GHz by default (its firmware country code marks 5 GHz as passive),
Intel cards always use 2.4 GHz. Everything can be changed in `Network → Wireless`.

```
wifi-autoconf --dry-run   # show what would be configured
wifi-autoconf --force     # configure all radios again
```

## ZeroTier gateway

`Services → ZeroTier Gateway`, two modes:

+ **Join a network** (my.zerotier.com, free account):
  1. create a network on https://my.zerotier.com, copy the network ID
  2. enter it in LuCI, enable, `Save & Apply`
  3. on my.zerotier.com authorize this device, set a fixed IP for it (e.g. `10.147.20.1`) and
     add the managed route `0.0.0.0/0` via that IP
+ **Own controller** (no account, network created and managed on this device, clients are
  authorized in LuCI). The ZeroTier controller code is licensed for non-commercial use only
  and is therefore **not included** in the published images, build it yourself:
  `ZT_CONTROLLER=1 ./openwrt/build.sh` (or Actions → build → Run workflow → "Add ZeroTier network controller").

Clients: install ZeroTier, join the network ID, enable **Allow Default Route Override**
(Windows / macOS: "Route all traffic through ZeroTier", Android / iOS: "Route via ZeroTier").
The device NATs ZeroTier clients to its internet uplink (WAN: 5G modem, Wi-Fi client, ...;
if the uplink is the LAN port enable `LAN access`).

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
