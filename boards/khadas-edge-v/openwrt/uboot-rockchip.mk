# package/boot/uboot-rockchip/Makefile: the Edge-V U-Boot
define U-Boot/khadas-edge-v-rk3399
  $(U-Boot/rk3399/Default)
  NAME:=Khadas Edge-V
  BUILD_DEVICES:= \
    khadas_edge-v
endef

  khadas-edge-v-rk3399 \
