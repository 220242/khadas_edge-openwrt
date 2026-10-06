#!/bin/bash
## Boot test of the x86 images in QEMU: every bootable image of a variant
## boots (SeaBIOS / UEFI), the first boot scripts run, the uplink gets an
## address by DHCP, LuCI / SSH answer and the main services run.
##
## USAGE
##   ./openwrt/test/qemu-smoke.sh VARIANT [DIR]
##
##   VARIANT  x86-64-vm (qcow2), x86-64-pc (efi + bios), i386-pc (bios)
##   DIR      images of imagebuilder.sh (default out/VARIANT)
##
## ENV
##   SMOKE_ONLINE=1   also check Internet access from the guest (apk update)
##   SMOKE_TIMEOUT=   seconds to wait for the web interface (default 180
##                    with KVM, 600 without)
##   SMOKE_LOGS=      directory for the serial console logs (default DIR)
##   ROOT_PW=khadasedge  root password set by 98-khadas-network

set -euo pipefail

VARIANT=${1:-}
DIR=${2:-out/$VARIANT}
ONLINE=${SMOKE_ONLINE:-1}
ROOT_PW=${ROOT_PW:-khadasedge}
LOGS=${SMOKE_LOGS:-$DIR}

log() { echo "[i] $*" >&2; }
die() { echo "[e] $*" >&2; exit 1; }

case "$VARIANT" in
	x86-64-vm) QEMU=qemu-system-x86_64 HOST=openwrt-vm IMAGES="*.qcow2" ;;
	x86-64-pc) QEMU=qemu-system-x86_64 HOST=openwrt-pc IMAGES="*-efi.img.gz *-bios.img.gz" ;;
	i386-pc)   QEMU=qemu-system-i386   HOST=openwrt-i386 IMAGES="*-bios.img.gz" ;;
	*) sed -n 's/^## \{0,1\}//p' "$0" >&2; exit 1 ;;
esac
[ -d "$DIR" ] || die "no directory $DIR"
command -v "$QEMU" >/dev/null || die "no $QEMU (apt install qemu-system-x86)"
command -v sshpass >/dev/null || die "no sshpass (apt install sshpass)"
mkdir -p "$LOGS"

ACCEL=tcg TIMEOUT=600 QEMU_CPU=max
[ -w /dev/kvm ] && ACCEL=kvm TIMEOUT=180 QEMU_CPU=host
# i386 image: Pentium 4 class (SSE2, no 64 bit), QEMU has no pentium4 model
[ "$QEMU" = qemu-system-i386 ] && QEMU_CPU=n270
TIMEOUT=${SMOKE_TIMEOUT:-$TIMEOUT}

# packages of the image decide what is checked (docker only where installed)
MANIFEST=$(ls "$DIR"/*.manifest 2>/dev/null | head -n 1 || true)
has_pkg() { [ -n "$MANIFEST" ] && grep -q "^$1 - " "$MANIFEST"; }

WORKDIR=$(mktemp -d)
QPID=
cleanup() {
	[ -n "$QPID" ] && kill "$QPID" 2>/dev/null && wait "$QPID" 2>/dev/null
	rm -rf "$WORKDIR"
}
trap cleanup EXIT

free_port() {
	python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}

FAILS=0
ok()   { echo "  ok   $*"; }
fail() { echo "  FAIL $*"; FAILS=$((FAILS + 1)); }
warn() { echo "  warn $*"; }

# boot IMAGE: start QEMU in the background, serial console to $SERIAL
boot() {
	local img="$1" disk fw=bios
	case "$img" in
		*.img.gz)
			disk=$WORKDIR/disk.img
			gzip -dc "$img" > "$disk" 2>/dev/null || true	# trailing metadata
			[ -s "$disk" ] || die "can not unpack $img"
			FMT=raw ;;
		*.qcow2) disk=$img FMT=qcow2 ;;
		*) die "unknown image $img" ;;
	esac
	case "$img" in *-efi.img.gz) fw=efi ;; esac

	# shellcheck disable=SC2054
	local args=(-machine "q35,accel=$ACCEL" -cpu "$QEMU_CPU" -smp 2 -m 1024
		-display none -monitor none -serial "file:$SERIAL" -no-reboot
		-snapshot -drive "file=$disk,format=$FMT,if=virtio"
		-netdev "user,id=wan,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22,hostfwd=tcp:127.0.0.1:$HTTP_PORT-:80,hostfwd=tcp:127.0.0.1:$HTTPS_PORT-:443"
		-device virtio-net-pci,netdev=wan)
	[ "$QEMU" = qemu-system-i386 ] && args[1]="pc,accel=$ACCEL"	# no PCIe on a Pentium 4
	if [ "$fw" = efi ]; then
		local code vars
		code=$(ls /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd 2>/dev/null | head -n 1 || true)
		vars=$(ls /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd 2>/dev/null | head -n 1 || true)
		[ -n "$code" ] && [ -n "$vars" ] || die "no OVMF UEFI firmware (apt install ovmf)"
		cp "$vars" "$WORKDIR/vars.fd"
		args+=(-drive "if=pflash,format=raw,readonly=on,file=$code"
			-drive "if=pflash,format=raw,file=$WORKDIR/vars.fd")
	fi
	log "boot $(basename "$img") ($fw, $ACCEL): $QEMU ${args[*]}"
	"$QEMU" "${args[@]}" &
	QPID=$!
}

ssh_run() {
	sshpass -p "$ROOT_PW" ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10 \
		root@127.0.0.1 "$@"
}

# wait until the web interface answers (the guest is up, uci-defaults done:
# the firewall lets the "home network" in only after 98-khadas-network)
wait_up() {
	local t=0
	while [ $t -lt "$TIMEOUT" ]; do
		kill -0 "$QPID" 2>/dev/null || { fail "QEMU exited (reboot / crash)"; return 1; }
		if curl -ksf -o /dev/null --max-time 5 "https://127.0.0.1:$HTTPS_PORT/cgi-bin/luci/" ||
		   curl -sf -o /dev/null --max-time 5 "http://127.0.0.1:$HTTP_PORT/"; then
			ok "web interface answers after ${t}s"
			return 0
		fi
		sleep 5
		t=$((t + 5))
	done
	fail "no web interface after ${TIMEOUT}s"
	return 1
}

check() {
	local out

	if grep -qE 'Kernel panic|end Kernel panic|Unable to mount root' "$SERIAL"; then
		fail "kernel panic, see $SERIAL"
	fi

	out=$(curl -ksL --max-time 15 "https://127.0.0.1:$HTTPS_PORT/cgi-bin/luci/" || true)
	echo "$out" | grep -qi 'luci' && ok "LuCI login page (HTTPS)" || fail "no LuCI login page on HTTPS"

	# SSH: dropbear may start a little after uhttpd
	local t=0
	until ssh_run true 2>/dev/null; do
		t=$((t + 5))
		[ $t -lt 60 ] || { fail "SSH login root / $ROOT_PW"; return; }
		sleep 5
	done
	ok "SSH login root / $ROOT_PW"

	out=$(ssh_run 'ls /etc/uci-defaults' 2>&1 || true)
	[ -z "$out" ] && ok "every first boot script (uci-defaults) succeeded" ||
		fail "first boot scripts left in /etc/uci-defaults (they failed): $(echo "$out" | tr '\n' ' ')"

	out=$(ssh_run 'uci -q get system.@system[0].hostname' 2>&1 || true)
	[ "$out" = "$HOST" ] && ok "host name $HOST" || fail "host name '$out', expected $HOST"

	out=$(ssh_run 'uci -q get network.wan.proto; uci -q get network.lan.ipaddr' 2>&1 | tr '\n' ' ' || true)
	[ "$out" = "dhcp 192.168.77.1/24 " ] && ok "uplink DHCP, LAN 192.168.77.1/24" ||
		fail "network config: $out (expected: dhcp 192.168.77.1/24)"

	out=$(ssh_run '. /usr/share/libubox/jshn.sh; json_load "$(ubus call network.interface.wan status)"; json_get_var up up; json_select ipv4-address && json_select 1 && json_get_var a address; echo "$up $a"' 2>&1 || true)
	case "$out" in
		"1 "?*) ok "uplink up, DHCP address ${out#1 }" ;;
		*) fail "uplink without a DHCP address: $out" ;;
	esac

	local svc svcs="uhttpd dropbear rpcd dnsmasq firewall umdns"
	has_pkg dockerd && svcs="$svcs dockerd"
	for svc in $svcs; do
		[ "$svc" = firewall ] && {
			ssh_run 'nft list chain inet fw4 input_wan' >/dev/null 2>&1 &&
				ok "firewall (fw4) loaded" || fail "firewall (fw4) not loaded"
			continue
		}
		ssh_run "/etc/init.d/$svc running" >/dev/null 2>&1 &&
			ok "service $svc running" || fail "service $svc not running"
	done

	if has_pkg dockerd; then
		t=0
		until ssh_run 'docker info --format "{{.ServerVersion}}"' >/dev/null 2>&1; do
			t=$((t + 5))
			[ $t -lt 90 ] || break
			sleep 5
		done
		out=$(ssh_run 'docker info --format "{{.ServerVersion}}"' 2>&1 || true)
		[ $t -lt 90 ] && ok "Docker $out" || fail "docker info: $out"
	fi

	# the own feed packages of this image are installed and LuCI knows them
	local p
	for p in luci-app-zt-gateway luci-app-docker-apps; do
		has_pkg "$p" || continue
		ssh_run "apk info -e $p" >/dev/null 2>&1 && ok "package $p installed" ||
			fail "package $p (in the manifest) not installed"
	done

	if [ "$ONLINE" = 1 ]; then
		if out=$(ssh_run 'apk update 2>&1' 2>&1); then
			ok "Internet from the guest, apk update"
		else
			fail "apk update: $(echo "$out" | tail -n 3)"
		fi
	fi

	out=$(ssh_run 'dmesg | grep -iE "call trace|BUG:|oops" | head -n 5' 2>/dev/null || true)
	[ -z "$out" ] || warn "kernel log: $out"
}

set -f
read -r -a pats <<< "$IMAGES"
set +f
shopt -s nullglob
n=0
for pat in "${pats[@]}"; do
	for img in "$DIR"/$pat; do
		n=$((n + 1))
		name=$(basename "$img")
		SERIAL=$LOGS/serial-$name.log
		SSH_PORT=$(free_port) HTTP_PORT=$(free_port) HTTPS_PORT=$(free_port)
		echo "== $name"
		: > "$SERIAL"
		boot "$img"
		wait_up && check
		kill "$QPID" 2>/dev/null || true
		wait "$QPID" 2>/dev/null || true
		QPID=
		rm -f "$WORKDIR/disk.img"
	done
done
[ "$n" -gt 0 ] || die "no image ($IMAGES) in $DIR"

if [ "$FAILS" -gt 0 ]; then
	echo "[e] $VARIANT: $FAILS check(s) failed, serial console logs in $LOGS" >&2
	exit 1
fi
log "$VARIANT: $n image(s) passed"
