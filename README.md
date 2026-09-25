# khadas edge openwrt

OpenWrt 25.12 for **Khadas Edge-V** https://docs.khadas.com/edge/ (RockChip RK3399, VIM form factor),
**NanoPi R5C / Zero2**, **Orange Pi Zero2**, **Raspberry Pi Zero / Zero 2 W**, **x86_64** PCs,
**virtual machines** (Proxmox, QEMU, VMware, VirtualBox, Hyper-V) and **32-bit** PCs.

Branch `nokvm`: no KVM / QEMU virtual machine manager on the board (VMs belong to Proxmox),
all images but the full Edge-V one with the official OpenWrt kernel (official kmods).

**Firmware selector**: [selector/](selector/index.html) - on GitHub Pages
(`https://<owner>.github.io/<repo>/`, Settings → Pages → Source: GitHub Actions, and
Settings → Environments → github-pages → allow the `nokvm` branch; workflow `static.yml`), lists the
images of the GitHub releases per device with install instructions.

![khadas vims openwrt](pics/khadas_vim_openwrt.jpg)

## Change logs

+ [README.changes.md](README.changes.md)

## What's inside

Full OpenWrt source build (`rockchip/armv8` target, Linux 6.12, mainline U-Boot + TF-A),
Khadas Edge-V added as an OpenWrt device. Board specific files (dtb, dts, U-Boot, Wi-Fi firmware):
[boards/khadas-edge-v](boards/khadas-edge-v).

+ **Plug and play**: Ethernet is the uplink (DHCP), the board shows up in the home router as
  `khadas-edge`; web interface, SSH, Docker apps from the home network; HDMI console
  (boot loader + Linux, login with a USB keyboard) prints the addresses, see [First boot](#first-boot)
+ **Onboard Wi-Fi works out of the box**: AMPAK AP6398S (BCM4359) with the Khadas firmware + NVRAM,
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

GitHub Actions builds on every push (Actions → build → artifacts), a `v*` tag makes a release
with all images (the firmware selector reads the releases):

| device | file | build |
|---|---|---|
| Khadas Edge-V | `openwrt-25.12.5-rockchip-armv8-khadas_edge-v-squashfs-sysupgrade.img.gz` | own kernel + ImageBuilder, ~5 min (kernel ~2 h, only when it changes) |
| Khadas Edge-V + KVM | `openwrt-25.12.5-rockchip-armv8-khadas_edge-v-kvm-squashfs-sysupgrade.img.gz` | own kernel (`KVM=1`) + ImageBuilder |
| PC / server x86_64 | `openwrt-25.12.5-x86-64-pc-efi.img.gz` (UEFI + BIOS), `…-pc-bios.img.gz` | ImageBuilder, ~15 min |
| virtual machine x86_64 | `openwrt-25.12.5-x86-64-vm.qcow2` (Proxmox / QEMU), `.vmdk` (VMware), `.vdi` (VirtualBox), `.vhdx` (Hyper-V), `.img.gz` | ImageBuilder |
| 32-bit PC, Pentium 4 and newer | `openwrt-25.12.5-i386-pc-bios.img.gz` | ImageBuilder |
| Khadas Edge-V, official kernel | `openwrt-25.12.5-edge-v-official-sysupgrade.img.gz` | ImageBuilder + [boards/khadas-edge-v](boards/khadas-edge-v) |
| NanoPi R5C | `openwrt-25.12.5-nanopi-r5c-sysupgrade.img.gz` | ImageBuilder |
| NanoPi Zero2 | `openwrt-25.12.5-nanopi-zero2-sysupgrade.img.gz` | ImageBuilder + [boards/nanopi-zero2](boards/nanopi-zero2) |
| Orange Pi Zero2 | `openwrt-25.12.5-orangepi-zero2-sysupgrade.img.gz` | ImageBuilder |
| Raspberry Pi Zero / Zero W | `openwrt-25.12.5-rpi-zero-factory.img.gz`, `-sysupgrade` | ImageBuilder |
| Raspberry Pi Zero 2 W | `openwrt-25.12.5-rpi-zero2-factory.img.gz`, `-sysupgrade` | ImageBuilder |

**Edge-V: three variants.** `edge-v-kvm` = the full image + virtual machines on the board
(KVM kernel, QEMU, `Services → Virtual Machines`: arm64 guests with UEFI, virtio, VNC).
**Full or official kernel.** The full image (source build) has the HDMI console and the root
file system on a USB SSD, its kernel differs from the official one, so kmods come from this project's
repository. `edge-v-official` uses the official rockchip kernel (Edge-V dtb + U-Boot added by the
ImageBuilder job): no HDMI console after U-Boot, no root on USB (the SSD works as a data disk),
`apk add kmod-…` from downloads.openwrt.org.

**Own kernels: [khadas-kernels](https://github.com/220242/khadas-kernels).** The Edge-V kernels
(HDMI + USB SSD, KVM) are built from source only when something they depend on changes
([openwrt/kernel-key.sh](openwrt/kernel-key.sh): kernel patches, kernel options of the
diffconfigs, the target specific own packages, [openwrt/kernel-rev](openwrt/kernel-rev)). The
job `kernel` publishes release `kernel-25.12.5-<variant>-<key>` there (ImageBuilder of that
kernel) and branch `apk-25.12.5-<variant>-<key>` (apk repository: every kmod, target packages,
the khadas feed, QEMU with edk2). Job `ib-edge-v` builds the images with that ImageBuilder and
the packages of [openwrt/diffconfig](openwrt/diffconfig) in minutes. Writing needs the secret
`KERNELS_TOKEN` (fine-grained token, `khadas-kernels`, Contents: read and write).

The jobs run in parallel. ImageBuilder images: official OpenWrt kernel (kmods from downloads.openwrt.org
work), package sets in [openwrt/ib/packages](openwrt/ib/packages):

+ `x86-64-pc`: Wi-Fi AX / BE cards with access point autoconfig, 4G / 5G modems, Docker + one click
  apps, ZeroTier gateway, 2.5G / 10G network cards
+ `x86-64-vm`: Docker + apps, ZeroTier gateway, `qemu-ga` (virtio / vmxnet3 / Hyper-V drivers are in the kernel)
+ `i386-pc`: Wi-Fi, modems, ZeroTier (no Docker)
+ `edge-v-official`, `nanopi-r5c`: Wi-Fi (PCIe + USB), modems, Docker; `nanopi-zero2`, `orangepi-zero2`:
  USB Wi-Fi, Docker; `rpi-zero`, `rpi-zero2`: onboard + USB Wi-Fi (no Ethernet: Wi-Fi `OpenWrt` /
  `khadasedge`, http://192.168.77.1)
+ host name per image (`khadas-edge`, `nanopi-r5c`, `rpi-zero`, `openwrt-pc`, ...), `http://<name>.local/`
+ one network port (typical VM): DHCP uplink like the Edge-V; two or more: `eth0` LAN 192.168.1.1, `eth1` WAN

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

+ [openwrt/patches](openwrt/patches) - Khadas Edge-V device (U-Boot with HDMI), USB UAS built in
+ [openwrt/ib](openwrt/ib) - x86 images: `sdk-feed.sh` (own packages with the official SDK),
  `imagebuilder.sh x86-64-pc|x86-64-vm|i386-pc|edge-v-official|nanopi-r5c|nanopi-zero2|orangepi-zero2|rpi-zero|rpi-zero2`;
  boards OpenWrt does not have (Edge-V, NanoPi Zero2) are added from `boards/*/board.conf` (dtb, U-Boot)
+ [openwrt/diffconfig](openwrt/diffconfig) - package selection
+ [openwrt/feed](openwrt/feed) - own packages:
  `luci-app-zt-gateway` (ZeroTier gateway), `luci-app-docker-apps`
  (one click Docker apps), `khadas-storage` + `luci-app-khadas-storage` (install to disk, expand root),
  `khadas-wifi-autoconf` (Wi-Fi AP setup), `khadas-edge-wifi-firmware` (AP6398S firmware),
  `khadas-edge-display` (HDMI console: `kmod-drm-rockchip`, `khadas-edge-console`)
+ [openwrt/files](openwrt/files) - rootfs overlay

## Build on Windows 11

`windows/build-khadas-edge.ps1` does everything on the `D:` drive: enables WSL2 (asks for admin rights and a
reboot only if WSL is missing, continues after the reboot by itself), downloads the official Ubuntu 24.04 WSL
image (SHA256 checked) to `D:\KhadasEdgeBuild\wsl`, installs the build dependencies, fetches the project and
builds. Images: `D:\KhadasEdgeBuild\out`, logs: `D:\KhadasEdgeBuild\logs`. Needs ~60 GB free on `D:`.

PowerShell:

```
iwr https://raw.githubusercontent.com/220242/khadas_edge-openwrt/nokvm/windows/build-khadas-edge.ps1 -OutFile D:\build-khadas-edge.ps1
powershell -ExecutionPolicy Bypass -File D:\build-khadas-edge.ps1
```

or double click `windows\build-khadas-edge.cmd` in a checkout. Options: `-Root E:\dir`, `-Jobs 8`,
`-Clean`, `-NoBuild` (only prepare, then `make menuconfig` in `\\wsl$\khadas-build\home\builder\khadas_edge-openwrt\build\openwrt`),
`-ZtController`, `-Uninstall`, `-Targets edge-v,edge-v-official,nanopi-r5c,x86-64-vm,...` (or `all`;
ImageBuilder targets take minutes: official SDK + ImageBuilder). Running it again updates the project and rebuilds only what changed.

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
  kernel (`kernel=6.12.94~<hash>`); the Edge-V kernel has USB UAS built in (root on a USB SSD)
  and the HDMI driver, so its hash differs and apk refuses them. The x86 images use the official
  kernel: there `apk add kmod-…` works from downloads.openwrt.org
+ so the kernel build makes **every kmod** (`CONFIG_ALL_KMODS`) for this kernel and publishes
  them in [khadas-kernels](https://github.com/220242/khadas-kernels), branch
  `apk-25.12.5-<variant>-<key>` (`targets/` kmods, `khadas/` own packages); the image uses it
  (`/etc/khadas-apk-repo`, `/etc/apk/repositories.d/distfeeds.list`):
  `apk update && apk add kmod-usb-net-rtl8152`
+ local builds (`./openwrt/build.sh`) have that feed disabled; their kmods are in
  `out/apk-repo` (`apk add --allow-untrusted ./kmod-….apk`)
+ old `apk-<run id>-…` branches of this repository are not used any more, delete them in GitHub

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
  resized on the next boot before it is mounted. Docker images can use the whole disk.

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
Onboard AP6398S uses 2.4 GHz by default (the most compatible setting for its firmware country code),
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
  `ZT_CONTROLLER=1 ./openwrt/build.sh`.

Clients: install ZeroTier, join the network ID, enable **Allow Default Route Override**
(Windows / macOS: "Route all traffic through ZeroTier", Android / iOS: "Route via ZeroTier").
The device NATs ZeroTier clients to its internet uplink (`wan`: Ethernet, 5G modem, Wi-Fi client).

## Legacy build

`scripts/build` - old repack build (Khadas 5.14 kernel + OpenWrt armsr userspace),
no AX / BE Wi-Fi drivers in that kernel.

## related projects

+ https://github.com/hyphop/khadas-openwrt (upstream, VIMs + Edge)
+ https://github.com/openwrt/openwrt

## links

+ https://openwrt.org/
+ https://docs.khadas.com/edge/
+ https://github.com/khadas
