# OpenWrt Khadas Change log

## nokvm: more boards, Edge-V on the official kernel

+ `edge-v-official`: Khadas Edge-V with the official rockchip kernel and kmods (ImageBuilder,
  device + dtb + U-Boot injected from `boards/khadas-edge-v`), no HDMI console / USB SSD root
+ NanoPi R5C, Orange Pi Zero2, Raspberry Pi Zero / Zero W, Raspberry Pi Zero 2 W (official
  profiles), NanoPi Zero2 (RK3528, not in OpenWrt 25.12.5: dtb from Linux 6.18 compiled with the
  OpenWrt kernel tree, generic RK3528 U-Boot, `boards/nanopi-zero2`)
+ `i386-legacy` removed
+ stable MAC from the eMMC / SD CID for the injected boards, host name + SSID per image
+ package lists: `wificore`, `wifipci`, `wifiusb`; optional packages with a dependency (`?pkg:dep`)

## nokvm: Edge-V + x86, firmware selector

+ branch `nokvm`: no KVM in the Edge-V kernel, no QEMU / `luci-app-kvm` (virtual machines belong
  to Proxmox); USB UAS stays built in (root on a USB SSD)
+ x86 images with the official ImageBuilder (official kernel, kmods from downloads.openwrt.org):
  `x86-64-pc` (UEFI + BIOS; Wi-Fi, modems, Docker, NICs), `x86-64-vm` (qcow2 / vmdk / vdi / vhdx / img.gz,
  qemu-ga), `i386-pc` (Pentium 4+), `i386-legacy` (i486 / Pentium); own LuCI apps built with the
  official SDK (`openwrt/ib`), parallel CI jobs, one release per `v*` tag
+ firmware selector (`selector/`, GitHub Pages): device → images of a release, SHA256, install steps
  (Proxmox / QEMU / VMware / VirtualBox / Hyper-V)
+ `boards/khadas-edge-v`: dts, dtb, U-Boot (HDMI) binaries + config, boot script, Wi-Fi firmware
+ Docker firewall defaults (`96-docker-firewall`) for every image; one network port = DHCP uplink
  also on x86 (VMs)
+ Windows script: `-Targets` (edge-v, x86-64-pc, x86-64-vm, i386-pc, i386-legacy, all)

## Edge-V: first boot, HDMI, kmods

+ only Khadas Edge-V is built (Edge / Edge-Captain profiles removed)
+ Ethernet is the uplink (DHCP client, hostname `khadas-edge`, mDNS `khadas-edge.local`): the board
  shows up in the home router; before, it was a LAN port with the static 192.168.1.1 and its own
  DHCP server, invisible in the router's client list (and clashing with routers on 192.168.1.1)
+ LAN = Wi-Fi access point bridge 192.168.77.1/24; web interface, SSH, Docker apps and VMs are
  reachable from private addresses on the uplink (home network), not from the Internet;
  root password `khadasedge` on a fresh install
+ HDMI output: U-Boot with video (logo + boot messages), kernel `kmod-drm-rockchip` (VOP + DW HDMI,
  fbcon), console on tty1 with a USB keyboard, addresses printed on the screen
  (the previous image had no display support at all: a black screen was expected)
+ Docker with fw4: `docker` zone forwards to `wan` and from `lan` (containers had no Internet
  through a WAN uplink), dockerd's own WAN block rule removed (fw4 already blocks the Internet)
+ every kmod of this kernel is built (`CONFIG_ALL_KMODS`) and published as an apk repository for
  release / manual builds (branch `apk-<run id>-<attempt>`), the image uses it: official kmods do not
  match a kernel with KVM / built-in USB storage
+ MAC address from the eMMC CID (`mmcblk2`), stable with or without an SD card

## OpenWrt Khadas Edge 25.12.5 source build

+ full OpenWrt 25.12.5 source build: rockchip/armv8, Linux 6.12, mainline U-Boot 2025.10 + TF-A
+ new devices: Khadas Edge, Edge-V, Edge-Captain
+ kernel with KVM
+ Wi-Fi AX / BE: Intel AX200 / AX210 / BE200, MediaTek MT7921 / MT7922 / MT7925 / MT7915 / MT7916 / MT7996,
  Realtek RTL8852AE / BE / CE, RTL8851BE, RTL8922AE, Qualcomm WCN6855 / WCN7850, onboard AP6356S
+ 4G / 5G modems: ModemManager, QMI, MBIM, NCM, MHI (M.2 PCIe)
+ virtual machines: QEMU/KVM + LuCI app `luci-app-kvm` (Services → Virtual Machines)
+ containers: Docker (luci-app-dockerman), LXC (luci-app-lxc)
+ GitHub Actions build + release
+ onboard AP6356S: Khadas BCM4356A2 firmware + NVRAM (OpenWrt cypress firmware is for BCM4356A3),
  no clm_blob, access point enabled out of the box
+ khadas-wifi-autoconf: access point on every Wi-Fi card with a band / channel the driver allows for AP
  (Intel AX200 / AX210 / BE200: 2.4 GHz)
+ ZeroTier internet gateway (luci-app-zt-gateway): join my.zerotier.com network or own controller
  (optional build, non-commercial license)
+ KVM: pmu=off and automatic big.LITTLE CPU pinning
+ PWM fan driver
+ Storage & Install: install to USB SSD / NVMe / eMMC / SD (copy or image, settings kept, unique disk ID),
  boot from USB / NVMe via the eMMC / SD boot script, expand root partition + overlay to the whole disk
+ kernel: USB UAS built in (root on USB SSD)
+ Docker Apps: one click catalog (20 arm64 apps), Docker Hub search with port / volume detection,
  any registry image, compose URL / paste

## OpenWrt Khadas Edge rel 25.12.5

+ updated openwrt base to 25.12.5 (target armvirt -> armsr/armv8)
+ Khadas Edge (RK3399) only
+ apk package manager support (25.x+), opkg kept for 23.05 / 24.10
+ firewall: iptables fw3 by default (khadas 5.14 kernel has no nft nat modules),
  FIREWALL=fw4 optional
+ packages: samba36 -> samba4, wireguard -> wireguard-tools + luci-proto-wireguard,
  libpcre -> libpcre2, wpad-wolfssl -> wpad-mbedtls, + iperf3,
  triggerhappy removed (dropped from OpenWrt)
+ network config: netifd `device` / bridge `ports` syntax
+ preinit: use stock OpenWrt preinit + khadas hooks, failsafe off via 00_preinit.conf
+ travis-ci -> github actions

## OpenWrt Khadas rel 21.02.0

+ updated openwrt base to 21.02.0
+ testing new series

## OpenWrt Khadas rel 19.07.8

+ u-boot updated 2021.07+
+ linux kernel updated 5.14*
+ updated openwrt base to 19.07.8
  The current stable version series of OpenWrt is 19.07,
  with v19.07.8 being the latest release of the series.
  It was released on 7 August 2021.
+ fixed rootfs detection
+ simplify image names to BOARD.OpenWrt.servers.sd.VERSION.img

## OpenWrt Khadas rel 0.77

+ u-boot updated
+ linux kernel updated 5.13x
+ soc watchdog activated
+ nvme bootable
+ fix hdmi + nvme bug
+ updated openwrt base to 19.07.7

## OpenWrt Khadas rel 0.76

+ u-boot updates and fixes
+ linux kernel updates and fixes

## OpenWrt Khadas rel 0.75

+ updated openwrt base to 19.07.5

## OpenWrt Khadas rel 0.74

+ updated openwrt base to 19.07.4

## OpenWrt Khadas rel 0.73

+ linux kernel 5.7.7
+ updated openwrt base 19.07.3
+ fixed boot scripts
+ fixed eth mac for VIM3x
+ fixed sd boot problem with legacy uboot 
+ updated uboot

## OpenWrt Khadas rel 0.7

+ add Khadas Edge (rockchip rk3399) - https://docs.khadas.com/edge/
+ linux kernel 5.7
+ one kernel for amlogic and rockchip
+ wireguard
+ pcie + nvme
+ some other fixes

## OpenWrt Khadas rel 0.66

+ linux kernel fix usb-starage uas bug (just disable uas)
+ linux kernel other fixes ... 
+ uboot changed to last mainline khadas version
+ green screen bug fixed for any uboot version
+ uboot script autodetect rootfs
+ boot from usb storages

## OpenWrt Khadas rel 0.63

+ change default dns resolver all via https-dns
+ change firewall users scripts /etc/firewall.user
+ small configs changes
+ f2fs blacklisted - overlay troubles with f2fs usage

## OpenWrt Khadas rel 0.62

+ change default rel to OpenWrt 19.07.2
+ change default uboot to mainline
+ improve build tc

## OpenWrt Khadas rel 0.61

+ change default rel to OpenWrt 19.07.1
+ update image build scripts
+ improve uboot scripts and config
+ add mainline uboot support + root env store to emmc fat partition

## OpenWrt Khadas rel 0.6

+ Final release of OpenWrt 19.07.0
+ improve openwrt 19.07.X series
+ add WIFI modules support for VIM3 VIM3L boards ( sdio id 02D0:4359 AP6398S)
+ initial overlay build support
+ add f2fs overlay support

## OpenWrt Khadas rel 0.5

+ add VIM3 and VIM3L initial support (without on board wifi)
+ add new kernel for VIM3L
+ prepare build scripts for openwrt 19.07.X series
+ add RTL8153 Gigabit Ethernet Adapter ( USB3.0 - 0bda:8153 - r8152 )
+ USB3.0 expand ready
+ network config add - USB eth1 bridged with usb0 as LAN
+ https://github.com/hyphop/khadas-openwrt/releases/tag/19.07.0-rc2
+ https://www.reddit.com/r/openwrt/comments/e6uzmq/openwrt_19070rc2_for_khadas_vim3_vim3l_boards/

## OpenWrt Khadas rel 0.4

+ add SQM support https://openwrt.org/docs/guide-user/network/traffic-shaping/sqm
+ rebuild linux kernel and modules config
+ improve build scripts | `scripts/build +server` - build server variant
+ prepare build scripts for openwrt 19.07.X series `cat scripts/build_last_rel.md` https://openwrt.org/releases/19.07/notes-19.07.0-rc1
+ add NFS-kernel-server only for 19.07.X server series - `nfsd_test` script test

## OpenWrt Khadas rel 0.3.1

+ ethernet for VIM2 fixed, hotplug & reinit without bugs! OK

## OpenWrt Khadas rel 0.3

+ added support for VIM2 ( with wifi chip AP6356S VIM2.V14 test mode )
+ preinstalled samba, mdns, ttyd, thd + many other packages
+ fix ethernet for VIM2, but still not possible reinit ethernet interface for VIM2
+ improve startup speed - now is about 7 sec
+ LEDs indicators - supported
+ board buttons KEY_F KEY_P - custom usage KEY_F - reset wifi | KEY_P - power off
+ initial optimization for Ethernet USB MMC subsystems
+ many improves
+ change default hostname to openwrt-vim + mdns name to: openwrt-vim.local

## OpenWrt Khadas rel 0.2

+ usb 3g 4g modems - OK
+ improve build scripts
+ some changes

## OpenWrt Khadas rel 0.1

it's a firt release for Khadas  boards

+ vim1 ver 1.2 - OK
+ vim1 ver 1.4 - OK
+ mainline linux kernel 5.3.0-*
+ OPENWRT release 18.06.4
+ khadas fan - OK
+ usb otg net -> bridge lan
+ eth0 -> wan
+ wifi driver [ brcmfmac ]
+ wifi chips SDIO_ID=02D0:A9A6 brcm/brcmfmac43430-sdio for chip BCM43430/1  (AP6212) - OK
+ wifi chips SDIO_ID=02D0:A9BF brcm/brcmfmac43455-sdio for chip BCM4345/6, (AP6255 ) - OK
+ wifi chips SDIO_ID=02D0:4356 brcm/brcmfmac4356-sdio for chip BCM4356/2, (AP6356S) - TESTMODE
+ boot from SD - OK
+ SD -> eMMC installation - OK
+ boot from eMMC - OK
+ HDMI - OK
+ UART - OK
+ i2c  - OK
+ led  - OK
+ VPNs ready

