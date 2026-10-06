#!/usr/bin/env bash
## boot-test.sh IMAGE [bios|uefi]
##   boot an x86 image in QEMU and check its first boot, as a VM with one
##   network port in a home network: the port is the DHCP uplink, SSH and
##   LuCI answer from the private uplink side with the default password,
##   every first boot script ran, the services are up
##
## IMAGE   openwrt-VER-VARIANT.qcow2 / -efi.img.gz / -bios.img.gz / .img.gz
##         (x86-64-vm, x86-64-pc, i386-pc from imagebuilder.sh); the image
##         itself is not changed
## bios    SeaBIOS (default), uefi: OVMF (x86_64 only)
##
## ENV
##   HOST=          expected host name (default: from the variant)
##   PASSWORD=khadasedge
##   TIMEOUT=600    seconds for the boot (KVM: ~30 s, emulation: minutes)
##   INTERNET=1     check that the image reaches the Internet (0: skip)
##   LOG=out/boot-test   QEMU console log
##   PORT=10022     host ports PORT (SSH) and PORT+1 (HTTPS)

set -u
IMAGE=${1:?usage: boot-test.sh IMAGE [bios|uefi]}
FW=${2:-bios}
PASSWORD=${PASSWORD:-khadasedge}
TIMEOUT=${TIMEOUT:-600}
INTERNET=${INTERNET:-1}
PORT=${PORT:-10022}
SSH_PORT=$PORT HTTPS_PORT=$((PORT + 1))

log() { echo "[i] $*" >&2; }
die() { echo "[e] $*" >&2; exit 1; }

[ -f "$IMAGE" ] || die "no image $IMAGE"
for t in qemu-img sshpass curl; do
	command -v "$t" >/dev/null || die "$t missing (apt install qemu-utils sshpass curl)"
done

## variant from the canonical name openwrt-VER-VARIANT[-efi|-bios].EXT
base=$(basename "$IMAGE")
base=${base%.gz}; base=${base%.img}; base=${base%.qcow2}
base=${base%-efi}; base=${base%-bios}
VER=$(echo "$base" | sed -n 's/^openwrt-\([0-9][^-]*\)-.*/\1/p')
VARIANT=${base#openwrt-"$VER"-}
case "$VARIANT" in
	x86-64-pc) h=openwrt-pc ;;
	x86-64-vm) h=openwrt-vm ;;
	i386-pc) h=openwrt-i386 ;;
	*) h= ;;
esac
HOST=${HOST:-$h}
case "$VARIANT" in
	i386-*) QEMU=qemu-system-i386 ;;
	*) QEMU=qemu-system-x86_64 ;;
esac
command -v "$QEMU" >/dev/null || die "$QEMU missing (apt install qemu-system-x86)"

WORK=$(mktemp -d)
LOG=${LOG:-out/boot-test}
mkdir -p "$LOG"
CONSOLE=$LOG/console-$VARIANT-$FW.log
: > "$CONSOLE"
QPID=
cleanup() {
	[ -n "$QPID" ] && kill "$QPID" 2>/dev/null
	rm -rf "$WORK"
}
trap cleanup EXIT

## disk: qcow2 overlay over the image, or an unpacked copy of img.gz
case "$IMAGE" in
	*.qcow2)
		qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$IMAGE")" "$WORK/disk.qcow2"
		disk="file=$WORK/disk.qcow2,format=qcow2" ;;
	*.img.gz)
		gzip -dc "$IMAGE" > "$WORK/disk.img" 2>/dev/null || true	# trailing metadata
		[ -s "$WORK/disk.img" ] || die "can not unpack $IMAGE"
		disk="file=$WORK/disk.img,format=raw" ;;
	*) disk="file=$(realpath "$IMAGE"),format=raw,snapshot=on" ;;
esac

args=(-m 1024 -smp 2 -nographic -monitor none -serial "file:$CONSOLE" -no-reboot
	-drive "$disk,if=virtio"
	-nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22,hostfwd=tcp:127.0.0.1:$HTTPS_PORT-:443")
if [ -w /dev/kvm ]; then
	# i386: a 32-bit CPU model, the 32-bit kernel on "host" (64-bit EPYC) panics
	if [ "$QEMU" = qemu-system-i386 ]; then cpu=kvm32; else cpu=host; fi
	args+=(-enable-kvm -cpu "$cpu")
else
	log "no /dev/kvm: emulation, the boot is slow"
	# default CPU model: "max" crashes OVMF and warns on i386 SMP under TCG
fi
if [ "$FW" = uefi ]; then
	[ "$QEMU" = qemu-system-x86_64 ] || die "uefi: x86_64 images only"
	code=$(ls /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd 2>/dev/null | head -n 1)
	[ -n "$code" ] || die "no OVMF (apt install ovmf)"
	cp "${code/CODE/VARS}" "$WORK/vars.fd"
	args+=(-machine q35
		-drive "if=pflash,format=raw,readonly=on,file=$code"
		-drive "if=pflash,format=raw,file=$WORK/vars.fd")
fi

log "boot $VARIANT ($FW) $IMAGE, host ${HOST:-?}, console $CONSOLE"
"$QEMU" "${args[@]}" </dev/null >"$WORK/qemu.out" 2>&1 &
QPID=$!

SSH=(sshpass -p "$PASSWORD" ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5
	-o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive
	root@127.0.0.1)
run() { "${SSH[@]}" "$@" </dev/null; }

## wait for SSH with the default password (dropbear starts late in the boot)
start=$SECONDS
until run true 2>/dev/null; do
	kill -0 "$QPID" 2>/dev/null || { cat "$WORK/qemu.out" >&2; tail -n 50 "$CONSOLE" >&2; die "QEMU exited"; }
	grep -q 'Kernel panic' "$CONSOLE" && { grep -a -B 40 -m 1 'Kernel panic' "$CONSOLE" >&2; die "kernel panic"; }
	[ $((SECONDS - start)) -lt "$TIMEOUT" ] || { tail -n 50 "$CONSOLE" >&2; die "no SSH login after $TIMEOUT s"; }
	sleep 5
done
log "SSH login after $((SECONDS - start)) s"

## the rest of the boot: every init script started
for _ in $(seq 60); do
	grep -q 'init complete' "$CONSOLE" && break
	sleep 2
done

fail=0
check() {	# check NAME CMD... (CMD runs on the host)
	local name=$1; shift
	if out=$("$@" 2>&1); then
		echo "ok   $name"
	else
		echo "FAIL $name"
		[ -n "$out" ] && echo "$out" | sed 's/^/     /' | head -n 20
		fail=1
	fi
}
# retry for things that come up a bit after SSH (DHCP lease, dockerd)
retry() {	# retry SECONDS CMD...
	local t=$1; shift
	local end=$((SECONDS + t))
	until "$@"; do
		[ "$SECONDS" -lt "$end" ] || return 1
		sleep 3
	done
}

check "SSH root login with the default password" run true
check "first boot scripts done (/etc/uci-defaults empty)" \
	run 'left=$(ls /etc/uci-defaults 2>/dev/null); [ -z "$left" ] || { echo "left: $left"; false; }'
[ -n "$VER" ] && check "release $VER" \
	run ". /etc/openwrt_release; [ \"\$DISTRIB_RELEASE\" = '$VER' ] || { echo \"\$DISTRIB_RELEASE\"; false; }"
[ -n "$HOST" ] && check "host name $HOST" \
	run "h=\$(uci -q get system.@system[0].hostname); [ \"\$h\" = '$HOST' ] || { echo \"\$h\"; false; }"
check "one port: eth0 is the DHCP uplink (wan)" \
	run '[ "$(uci -q get network.wan.device)" = eth0 ] && [ "$(uci -q get network.wan.proto)" = dhcp ] &&
		[ "$(uci -q get network.lan.ipaddr)" = 192.168.77.1/24 ] || { uci show network; false; }'
check "uplink got a DHCP address" retry 60 \
	run 'ubus call network.interface.wan status | jsonfilter -e "@[\"ipv4-address\"][0].address" | grep -q .'
check "firewall: home network rule loaded" \
	run 'fw4 check >/dev/null && nft list ruleset | grep -q Allow-Home-Network'
check "services: dropbear, uhttpd, rpcd" \
	run 'for s in dropbear uhttpd rpcd; do /etc/init.d/$s running || { echo "$s not running"; exit 1; }; done'
check "LuCI login page (HTTPS)" \
	sh -c "curl -ks https://127.0.0.1:$HTTPS_PORT/cgi-bin/luci/ | grep -q luci_password"
check "LuCI login with the default password" \
	sh -c "curl -ks -o /dev/null -w '%{http_code}' -d 'luci_username=root&luci_password=$PASSWORD' \
		https://127.0.0.1:$HTTPS_PORT/cgi-bin/luci/ | grep -qx 302"
check "LuCI rejects a wrong password" \
	sh -c "curl -ks -o /dev/null -w '%{http_code}' -d 'luci_username=root&luci_password=wrong-$PASSWORD' \
		https://127.0.0.1:$HTTPS_PORT/cgi-bin/luci/ | grep -qvx 302"
if run '[ -x /etc/init.d/dockerd ]'; then
	check "Docker: dockerd answers" retry 90 run 'docker info >/dev/null 2>&1'
	check "Docker: firewall zone" run '[ "$(uci -q get firewall.docker.name)" = docker ]'
fi
[ "$INTERNET" = 1 ] && check "Internet through the uplink" retry 60 \
	run 'wget -q -T 10 -O /dev/null https://downloads.openwrt.org/'
check "no kernel oops / BUG" \
	run '! dmesg | grep -E "Oops|BUG:|Call Trace"'

run poweroff >/dev/null 2>&1 || true
for _ in $(seq 20); do kill -0 "$QPID" 2>/dev/null || break; sleep 1; done

[ "$fail" = 0 ] || { log "console: $CONSOLE"; die "$VARIANT ($FW): boot test failed"; }
log "$VARIANT ($FW): boot test passed"
