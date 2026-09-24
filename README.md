# khadas edge openwrt

OpenWrt for Khadas Edge boards https://docs.khadas.com/edge/ (RockChip RK3399)

![khadas vims openwrt](pics/khadas_vim_openwrt.jpg)

## Change logs

+ [README.changes.md](README.changes.md)

## supported Boards

+ [khadas Edge / Edge-V / Captain](https://docs.khadas.com/edge) - OK

## OpenWrt base

+ **25.12.x** (default) - `apk` package manager
+ 24.10.x / 23.05.x - `opkg` package manager

userspace comes from the official OpenWrt `armsr/armv8` rootfs,
kernel / dtb / u-boot - from Khadas releases (linux 5.14).

The Khadas 5.14 kernel is built without the nftables modules required by
`firewall4`, so the image uses the iptables based `firewall` (fw3)
by default. With a kernel that has them, set `FIREWALL=fw4`.

## Build

```
git clone https://github.com/220242/khadas_edge-openwrt.git
cd khadas_edge-openwrt

# ./scripts/build_prepare      # if some tools missed

# build openwrt for Edge (OpenWrt 25.12.x)
./scripts/build -e
#
./scripts/build -e emmc     # build openwrt for Edge emmc image
#
./scripts/build -e +servers # build openwrt server variant for Edge
#
./scripts/build -e -r       # force refresh package manager & lists
#
./scripts/build -e -rel=24.10.8          # build openwrt 24.10.8 (opkg)
echo REL=24.10.8 > scripts/build.conf.user # same, permanent
#
echo FIREWALL=fw4 >> scripts/build.conf.user # nftables firewall4
#
```

result: `/tmp/Edge.OpenWrt..sd.v25.12.5.img.gz`

required host tools: `rsync curl wget bash sfdisk gzip mkimage mksquashfs
mkfs.ext4 mkfs.vfat mdir mcopy`

## Installation

just write image to SD card

```
gzip -dc Edge.OpenWrt..sd.v25.12.5.img.gz | sudo dd bs=1M of=/dev/SD_PATH
sync
```

## install to emmc inside openwrt booted from sd

    root@openwrt:/# mmc_install_from_sd

## docs & how to

+ [files/docs](files/docs)
+ [README.openwrt.vims.md](README.openwrt.vims.md)

## related projects

+ https://github.com/hyphop/khadas-openwrt (upstream, VIMs + Edge)
+ https://github.com/hyphop/khadas-linux-kernel
+ https://github.com/hyphop/khadas-uboot
+ https://github.com/hyphop/khadas-rescue
+ https://github.com/hyphop/khadas-rescue-tools

## links

+ https://openwrt.org/
+ https://docs.khadas.com/edge/
+ https://github.com/khadas
+ https://docs.khadas.com
