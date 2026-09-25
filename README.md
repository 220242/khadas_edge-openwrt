# khadas edge openwrt

OpenWrt 25.12 for **Khadas Edge-V** https://docs.khadas.com/edge/ (RockChip RK3399, VIM form factor).

![khadas vims openwrt](pics/khadas_vim_openwrt.jpg)

## Change logs

+ [README.changes.md](README.changes.md)

## What's inside

Full OpenWrt source build (`rockchip/armv8` target, Linux 6.12, mainline U-Boot + TF-A),
Khadas Edge-V added as an OpenWrt device, kernel built with **KVM**.

+ **Plug and play**: Ethernet is the uplink (DHCP), the board shows up in the home router as
  `khadas-edge`; web interface, SSH, Docker apps from the home network; HDMI console
  (boot loader + Linux, login with a USB keyboard) prints the addresses, see [First boot](#first-boot)
+ **Onboard Wi-Fi works out of the box**: AP6356S (BCM4356A2) with the Khadas firmware + NVRAM,
  access point `Khadas-Edge` / password `khadasedge` (WPA2, 2.4 GHz channel 6), LAN `192.168.77.1`
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
+ **Kernel modules from the package manager**: every kmod of this kernel is built and published with
  the image, `apk add kmod-…` works, see [Packages](#packages-and-kernel-modules)
+ **Containers**
  + **one click Docker apps** - `Services → Docker Apps`: catalog of 20 apps (Portainer, Home Assistant,
    AdGuard Home, Nextcloud, Jellyfin, Syncthing, Vaultwarden, qBittorrent, Nginx Proxy Manager, WireGuard Easy, ...),
    Docker Hub search with automatic ports / volumes, any registry image, docker-compose URL or paste
  + Docker + docker-compose, LuCI `Docker` (luci-app-dockerman) for advanced management
  + LXC, LuCI `Services → LXC Containers`
+ **Storage** - `System → Storage & Install`: install OpenWrt to a USB SSD / NVMe / eMMC / SD card,
  boot from USB / NVMe, expand the root filesystem to the whole disk, see [Storage](#storage-usb-ssd-nvme)
+ storage: USB, NVMe (M.2 adapter), ext4 / btrfs, 2 GB root partition

## Images

GitHub Actions builds the image on every push (Actions → build → artifacts) and
publishes a release for `v*` tags:

+ `openwrt-25.12.5-rockchip-armv8-khadas_edge-v-squashfs-sysupgrade.img.gz`

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

+ [openwrt/patches](openwrt/patches) - Khadas Edge-V device (U-Boot with HDMI), KVM kernel config, QEMU for rockchip
+ [openwrt/diffconfig](openwrt/diffconfig) - package selection
+ [openwrt/feed](openwrt/feed) - own packages:
  `luci-app-kvm` (VM manager), `luci-app-zt-gateway` (ZeroTier gateway), `luci-app-docker-apps`
  (one click Docker apps), `khadas-storage` + `luci-app-khadas-storage` (install to disk, expand root),
  `khadas-wifi-autoconf` (Wi-Fi AP setup), `khadas-edge-wifi-firmware` (AP6356S firmware),
  `khadas-edge-display` (HDMI console: `kmod-drm-rockchip`, `khadas-edge-console`)
+ [openwrt/files](openwrt/files) - rootfs overlay

## Build on Windows 11

`windows/build-khadas-edge.ps1` does everything on the `D:` drive: enables WSL2 (asks for admin rights and a
reboot only if WSL is missing, continues after the reboot by itself), downloads the official Ubuntu 24.04 WSL
image (SHA256 checked) to `D:\KhadasEdgeBuild\wsl`, installs the build dependencies, fetches the project and
builds. Images: `D:\KhadasEdgeBuild\out`, logs: `D:\KhadasEdgeBuild\logs`. Needs ~60 GB free on `D:`.

PowerShell:

```
iwr https://raw.githubusercontent.com/220242/khadas_edge-openwrt/claude/festive-pasteur-grk0sc/windows/build-khadas-edge.ps1 -OutFile D:\build-khadas-edge.ps1
powershell -ExecutionPolicy Bypass -File D:\build-khadas-edge.ps1
```

or double click `windows\build-khadas-edge.cmd` in a checkout. Options: `-Root E:\dir`, `-Jobs 8`,
`-Clean`, `-NoBuild` (only prepare, then `make menuconfig` in `\\wsl$\khadas-build\home\builder\khadas_edge-openwrt\build\openwrt`),
`-ZtController`, `-Uninstall`. Running it again updates the project and rebuilds only what changed.

## Installation

The RK3399 boot ROM tries SPI flash, then eMMC, then the SD card, and starts the first
boot loader it finds. Edge-V comes with Android / Ubuntu on the eMMC, so an SD card alone
is ignored while the eMMC still has its boot loader.

+ **eMMC (recommended)**: boot [Krescue](https://docs.khadas.com/products/sbc/edge/)
  (or Oowow) from an SD card and write the `.img.gz` to the eMMC
+ **SD card**: write the image (balenaEtcher / Rufus take `.img.gz` directly, or
  `gzip -dc openwrt-*-khadas_edge-v-squashfs-sysupgrade.img.gz | sudo dd bs=1M of=/dev/SD_PATH`),
  then make the board skip the eMMC: erase the eMMC boot loader (Krescue), or use the Khadas
  "boot from external media" key sequence (docs.khadas.com → Edge)
+ if nothing shows up on HDMI at all, an old boot loader in the SPI flash may start first:
  erase the SPI flash with Krescue

## First boot

+ **HDMI**: the U-Boot logo and boot messages, then the Linux console with the device addresses
  (`wan … web: http://…`); press Enter for a shell (USB keyboard)
+ **Ethernet** = uplink (`wan`, DHCP client): connect it to the home router, the board shows up
  there as `khadas-edge` (also `http://khadas-edge.local/`)
+ **Wi-Fi** access point `Khadas-Edge` / `khadasedge` = LAN `192.168.77.1`, DHCP for clients,
  NAT to the uplink; http://192.168.77.1 works from Wi-Fi even without any uplink
+ web interface / SSH: user `root`, password **`khadasedge`** - **change it**
  (`System → Administration`); reachable from the home network (private addresses on the uplink:
  10/8, 172.16/12, 192.168/16) and from the Wi-Fi LAN, not from the Internet
+ other uplinks: 5G modem (ModemManager), Wi-Fi client (`Network → Wireless → Scan`)
+ settings kept over sysupgrade are not changed; the defaults are in
  [openwrt/files/etc/uci-defaults](openwrt/files/etc/uci-defaults)

## Packages and kernel modules

+ normal packages (`apk add …`, `System → Software`) come from downloads.openwrt.org
  (25.12.5, `aarch64_generic`): same release and ABI as this image
+ **kernel modules can not** come from there: official kmods are built for the official
  kernel (`kernel=6.12.94~<hash>`); this kernel has KVM and USB storage / UAS / NVMe built in
  (root on USB SSD), so its hash differs and apk refuses them (loading them anyway would crash:
  KVM changes kernel structures)
+ so the build makes **every kmod** (`CONFIG_ALL_KMODS`) for this kernel. Release (`v*` tag) and
  manual (Run workflow) builds publish them as an apk repository in the branch `apk-<run id>-<attempt>`
  (`targets/` kmods, `khadas/` own packages) and the image uses it
  (`/etc/khadas-apk-repo`, `/etc/apk/repositories.d/distfeeds.list`):
  `apk update && apk add kmod-usb-net-rtl8152`
+ other builds (and local builds) have that feed disabled; their kmods are in
  `out/apk-repo` (`apk add --allow-untrusted ./kmod-….apk`)
+ old `apk-*` branches are not deleted automatically, remove them in GitHub when not needed

## Virtual machines quick start

```
# storage for VMs, e.g. a USB SSD / NVMe
mkfs.ext4 /dev/nvme0n1 && mkdir -p /mnt/vm && mount /dev/nvme0n1 /mnt/vm
cd /mnt/vm && wget https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/debian-13.1.0-arm64-netinst.iso
```

`Services → Virtual Machines`: add VM, set disk `/mnt/vm/debian.qcow2`, disk size `16G`,
CD image, VNC display `0`, enable `Run`, `Save & Apply`, connect VNC client to `<board address>:5900`.

RK3399 is big.LITTLE (4x Cortex-A53 + 2x Cortex-A72): KVM vCPUs are pinned to one
core type with `CPU affinity` (default `4-5`, A72).

## Storage: USB SSD, NVMe

`System → Storage & Install`

+ **Install OpenWrt to disk**: USB SSD, NVMe, eMMC or SD card; source is a copy of
  the running system or an uploaded `sysupgrade.img.gz` (checked against the board). Settings are kept,
  the root partition uses the whole disk, the disk gets its own disk ID (two disks with the same image would
  otherwise have the same root `PARTUUID`).
+ **Boot from NVMe / USB disk**: the RK3399 boot ROM starts only from SPI flash, eMMC or SD card, so the
  boot loader stays there. With this option the boot script on the eMMC / SD card starts OpenWrt from an
  NVMe or USB disk when one is connected (`nvme 0`, `usb 0..3`), otherwise OpenWrt on the eMMC / SD card.
  Typical setup: flash the image to the SD card or eMMC, boot, install to the USB SSD with
  "Boot from this disk", reboot. The kernel has USB storage, UAS and NVMe built in (root on USB / NVMe).
+ **Expand root to the whole disk**: grows the root partition, the overlay filesystem (f2fs / ext4) is
  resized on the next boot before it is mounted. Docker images and VM disks can use the whole disk.

## Docker apps

`Services → Docker Apps`:

+ catalog: one click install, `docker-compose.yml` can be edited before the install, data in `/opt/docker-apps/<name>/`
+ Docker Hub search → Install: the image is pulled, exposed ports and volumes are detected and a
  compose file is generated (ports 22 / 53 / 80 / 443 are used by the router and move to 8022 / 8053 / 8080 / 8443)
+ any registry image (`ghcr.io/…`, `lscr.io/…`, `quay.io/…`), a `docker-compose.yml` URL or pasted YAML
+ start / stop / update (pull + recreate) / logs / delete for installed apps
+ published ports are reachable from the home network (uplink, private addresses) and the Wi-Fi LAN,
  not from the Internet; containers reach the Internet (firewall zone `docker` forwards to `wan`)

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
The device NATs ZeroTier clients to its internet uplink (`wan`: Ethernet, 5G modem, Wi-Fi client).

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
