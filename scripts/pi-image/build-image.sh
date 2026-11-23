#!/usr/bin/env bash
# Builds the «Argus Node» Raspberry Pi image from the official Raspberry Pi OS Lite (64-bit) image.
#
#   sudo scripts/pi-image/build-image.sh <raspios-lite-arm64.img[.xz]> <out.img>
#
# Used by .github/workflows/pi-image.yml on a native arm64 runner (ubuntu-24.04-arm), where the arm64 chroot runs
# without emulation. On x86_64 it also works if qemu-user-static is registered in binfmt_misc
# (apt install qemu-user-static binfmt-support) — slower, and not what CI does.
#
# What it does (the official image stays as it is otherwise, incl. cloud-init / Raspberry Pi Imager customisation):
#   1. unpacks the image, grows the root partition by ARGUS_GROW_MB (default 256 MB, for headroom), loop-mounts it;
#   2. /opt/argus-node: argus-node-linux.sh + static musl librpc_server*.so (android/app/src/main/jniLibs/arm64-v8a)
#      + the image helpers from scripts/pi-image/rootfs/opt/argus-node;
#   3. system user `argus`, systemd units argus-node.service / argus-firstboot.service / argus-pin-export.path;
#   4. hostname argus-node, SSH switched on via the official `ssh` file on the boot partition (no user, no password
#      is created: accounts come from Raspberry Pi Imager customisation / cloud-init or the first-boot wizard);
#   5. boot partition: argus.conf (settings template) + ARGUS-README.txt;
#   6. swap: Raspberry Pi OS Trixie's rpi-swap (zram) is kept; only if it is missing, systemd-zram-generator is added;
#   7. smoke test inside the chroot: the node starts as `argus`, secured mode gateway answers, PIN file and the UDP
#      beacon appear; then everything the test created is removed;
#   8. restores machine-id / SSH host keys if anything touched them, fstrim, fsck, unmount.
# Env: ARGUS_BASE_EXTRACT_SHA256 (verify the unpacked base image)  ARGUS_GROW_MB=256  ARGUS_BUILD_INFO="text"
#      ARGUS_SKIP_SMOKE=1 (skip step 7)
set -euo pipefail

log() { printf '\n[pi-image] %s\n' "$*" >&2; }
die() { printf '[pi-image] ERROR: %s\n' "$*" >&2; exit 1; }

[ $# -eq 2 ] || die "usage: sudo $0 <raspios-lite-arm64.img[.xz]> <out.img>"
BASE="$1"; OUT="$2"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
JNI="$REPO/android/app/src/main/jniLibs/arm64-v8a"
GROW_MB="${ARGUS_GROW_MB:-256}"
[ "$(id -u)" = 0 ] || die "needs root (loop devices, mount, chroot): sudo $0 …"
[ -f "$BASE" ] || die "base image not found: $BASE"

# ------------------------------------------------------------------ preflight
for t in losetup sfdisk e2fsck resize2fs mount umount chroot truncate fstrim xz sha256sum file systemctl; do
  command -v "$t" >/dev/null || die "missing tool: $t"
done
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] \
       || die "not an arm64 host and no qemu-aarch64 binfmt: apt install qemu-user-static binfmt-support (or use an arm64 runner)" ;;
esac
SO_FILES=(librpc_server.so librpc_server_dotprod.so librpc_server_i8mm.so)
for so in "${SO_FILES[@]}"; do
  [ -f "$JNI/$so" ] || die "missing $JNI/$so"
  desc="$(file -b "$JNI/$so")"
  case "$desc" in *ARM\ aarch64*) ;; *) die "$so is not an aarch64 ELF: $desc" ;; esac
  case "$desc" in *statically\ linked*|*static-pie\ linked*) ;; *) log "WARNING: $so does not look static: $desc" ;; esac
done
for f in argus-conf.sh argus-firstboot.sh argus-node-prestart.sh argus-node-service.sh argus-pin-export.sh; do
  [ -f "$HERE/rootfs/opt/argus-node/$f" ] || die "missing scripts/pi-image/rootfs/opt/argus-node/$f"
done

# ------------------------------------------------------------------ unpack + grow
log "unpacking $(basename "$BASE") → $OUT"
mkdir -p "$(dirname "$OUT")"
case "$BASE" in
  *.xz) xz -dc -T0 "$BASE" >"$OUT" ;;
  *) cp --sparse=always "$BASE" "$OUT" ;;
esac
if [ -n "${ARGUS_BASE_EXTRACT_SHA256:-}" ]; then
  got="$(sha256sum "$OUT" | cut -d' ' -f1)"
  [ "$got" = "$ARGUS_BASE_EXTRACT_SHA256" ] || die "unpacked base image sha256 $got != expected $ARGUS_BASE_EXTRACT_SHA256"
  log "base image sha256 OK ($got)"
fi
sfdisk -d "$OUT" >&2
[ "$(sfdisk -d "$OUT" | grep -c '^[^ ]*[0-9] : start=')" = 2 ] || die "expected exactly 2 partitions (bootfs + rootfs)"

if [ "$GROW_MB" -gt 0 ]; then
  log "growing the root partition by ${GROW_MB} MB"
  truncate -s "+${GROW_MB}M" "$OUT"
  echo ', +' | sfdisk --no-reread --no-tell-kernel -N 2 "$OUT" >&2
fi

MNT=""; LOOP=""; SMOKE_PID=""
kill_chroot_procs() { # anything still running with its root inside $MNT
  [ -n "$MNT" ] || return 0
  local p r
  for p in /proc/[0-9]*; do
    r="$(readlink "$p/root" 2>/dev/null || true)"
    case "$r" in "$MNT"|"$MNT"/*) kill -9 "${p#/proc/}" 2>/dev/null || true ;; esac
  done
}
cleanup() {
  set +e
  [ -n "$SMOKE_PID" ] && kill "$SMOKE_PID" 2>/dev/null
  kill_chroot_procs
  if [ -n "$MNT" ]; then
    for m in dev/pts dev proc sys boot/firmware ""; do
      mountpoint -q "$MNT/$m" && { umount "$MNT/$m" || umount -l "$MNT/$m"; }
    done
    rmdir "$MNT" 2>/dev/null
  fi
  [ -n "$LOOP" ] && losetup -d "$LOOP"
}
trap cleanup EXIT

LOOP="$(losetup --show -fP "$OUT")"
for _ in $(seq 1 20); do [ -b "${LOOP}p2" ] && break; udevadm settle 2>/dev/null || sleep 0.5; done
if [ ! -b "${LOOP}p1" ] || [ ! -b "${LOOP}p2" ]; then die "partitions of $LOOP did not appear"; fi
log "fsck + resize2fs ${LOOP}p2"
e2fsck -fy "${LOOP}p2" >&2 || [ $? -le 1 ] || die "e2fsck failed on the base image"
resize2fs "${LOOP}p2" >&2

MNT="$(mktemp -d /tmp/argus-pi-root.XXXXXX)"
mount "${LOOP}p2" "$MNT"
[ -d "$MNT/boot/firmware" ] || die "no /boot/firmware in the rootfs — not a Raspberry Pi OS Bookworm/Trixie image?"
mount "${LOOP}p1" "$MNT/boot/firmware"
for m in proc sys dev dev/pts; do mount --bind "/$m" "$MNT/$m"; done
in_chroot() { chroot "$MNT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C.UTF-8 "$@"; }
in_chroot /bin/true || die "cannot run arm64 binaries in the chroot"
log "base: $(grep PRETTY_NAME "$MNT/etc/os-release" | cut -d= -f2) · $(head -n1 "$MNT/boot/firmware/issue.txt" 2>/dev/null || echo '?')"
df -h "$MNT" "$MNT/boot/firmware" >&2

# things a build must never bake into an image: remember them, restore at the end
MACHINE_ID_BEFORE="$(cat "$MNT/etc/machine-id" 2>/dev/null || true)"
hostkeys() { local f out=""; for f in "$MNT"/etc/ssh/ssh_host_*; do [ -e "$f" ] && out+="${f##*/} "; done; printf '%s' "$out"; }
HOSTKEYS_BEFORE="$(hostkeys)"
RESOLV_BACKUP=""
APT_USED=0
apt_in_chroot() {
  if [ -z "$RESOLV_BACKUP" ]; then
    RESOLV_BACKUP="$MNT/etc/resolv.conf.argus-build"
    if [ -e "$MNT/etc/resolv.conf" ] || [ -L "$MNT/etc/resolv.conf" ]; then mv "$MNT/etc/resolv.conf" "$RESOLV_BACKUP"; else : >"$RESOLV_BACKUP.none"; fi
    cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"
  fi
  if [ "$APT_USED" = 0 ]; then in_chroot apt-get update; APT_USED=1; fi
  in_chroot env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

# ------------------------------------------------------------------ dependencies of the node script
if ! in_chroot python3 -c 'import json, socket, hashlib, hmac, secrets, threading' 2>/dev/null; then
  log "python3 (stdlib) missing in the image — installing"
  apt_in_chroot python3
fi
for t in bash hostname nproc awk tr; do in_chroot sh -c "command -v $t" >/dev/null || die "image lacks $t"; done

# ------------------------------------------------------------------ /opt/argus-node
log "installing /opt/argus-node"
install -d -m 0755 "$MNT/opt/argus-node"
install -m 0755 "$REPO/scripts/argus-node-linux.sh" "$MNT/opt/argus-node/argus-node-linux.sh"
for so in "${SO_FILES[@]}"; do install -m 0755 "$JNI/$so" "$MNT/opt/argus-node/$so"; done
install -m 0644 "$HERE/rootfs/opt/argus-node/argus-conf.sh" "$MNT/opt/argus-node/argus-conf.sh"
for f in argus-firstboot.sh argus-node-prestart.sh argus-node-service.sh argus-pin-export.sh; do
  install -m 0755 "$HERE/rootfs/opt/argus-node/$f" "$MNT/opt/argus-node/$f"
done
for u in argus-node.service argus-firstboot.service argus-pin-export.path argus-pin-export.service; do
  install -m 0644 "$HERE/rootfs/etc/systemd/system/$u" "$MNT/etc/systemd/system/$u"
done
{
  echo "Argus Node image"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "base: $(head -n1 "$MNT/boot/firmware/issue.txt" 2>/dev/null || echo '?')"
  [ -n "${ARGUS_BUILD_INFO:-}" ] && printf '%s\n' "$ARGUS_BUILD_INFO"
  (cd "$MNT/opt/argus-node" && sha256sum argus-node-linux.sh librpc_server*.so)
} >"$MNT/opt/argus-node/BUILD-INFO"

# ------------------------------------------------------------------ user, units, hostname, ssh, boot files
if ! in_chroot getent passwd argus >/dev/null; then
  in_chroot useradd --system --user-group --home-dir /var/lib/argus-node --no-create-home \
    --shell /usr/sbin/nologin --comment "Argus node" argus
fi
log "user: $(in_chroot id argus)"

systemctl --root="$MNT" enable argus-node.service argus-firstboot.service argus-pin-export.path >&2

echo argus-node >"$MNT/etc/hostname"
if grep -q '^127\.0\.1\.1' "$MNT/etc/hosts"; then
  sed -i 's/^127\.0\.1\.1.*/127.0.1.1\targus-node/' "$MNT/etc/hosts"
else
  printf '127.0.1.1\targus-node\n' >>"$MNT/etc/hosts"
fi

# official first-boot SSH switch (sshswitch.service enables ssh and deletes the file); no password is set anywhere
: >"$MNT/boot/firmware/ssh"
install -m 0644 "$HERE/bootfs/argus.conf" "$MNT/boot/firmware/argus.conf"
install -m 0644 "$HERE/bootfs/ARGUS-README.txt" "$MNT/boot/firmware/ARGUS-README.txt"

# ------------------------------------------------------------------ swap: keep rpi-swap (zram, Trixie default)
pkg_installed() { # shellcheck disable=SC2016 # ${Status} is a dpkg-query format field
  [ "$(in_chroot dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)" = "install ok installed" ]; }
if pkg_installed rpi-swap; then
  log "swap: rpi-swap (zram) present — keeping the Raspberry Pi OS defaults"
elif pkg_installed dphys-swapfile; then
  log "swap: dphys-swapfile (Bookworm) present — adding zram on top via systemd-zram-generator"
  apt_in_chroot systemd-zram-generator
  printf '[zram0]\nzram-size = min(ram / 2, 4096)\ncompression-algorithm = zstd\nswap-priority = 100\n' \
    >"$MNT/etc/systemd/zram-generator.conf"
else
  log "swap: no swap manager found — adding systemd-zram-generator"
  apt_in_chroot systemd-zram-generator
  printf '[zram0]\nzram-size = min(ram / 2, 4096)\ncompression-algorithm = zstd\nswap-priority = 100\n' \
    >"$MNT/etc/systemd/zram-generator.conf"
fi

# ------------------------------------------------------------------ smoke test (inside the image's userland)
if [ "${ARGUS_SKIP_SMOKE:-0}" != 1 ]; then
  log "smoke test: node as user argus, secured mode, beacon"
  uid="$(in_chroot id -u argus)"; gid="$(in_chroot id -g argus)"
  SD=/tmp/argus-smoke
  rm -rf "${MNT:?}$SD"; install -d -m 0750 -o "$uid" -g "$gid" "$MNT$SD"
  # ARGUS_TRUST_LOOPBACK=0: the gateway normally lets 127.x straight through (adb forward); here we want the
  # handshake greeting on loopback too. Beacon listener runs on the host (also unicast to 127.0.0.1).
  python3 - >"$MNT$SD.beacon" 2>&1 <<'PY' &
import json, socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", 50053)); s.settimeout(40)
while True:
    d, a = s.recvfrom(4096)
    try:
        b = json.loads(d)
    except ValueError:
        continue
    if b.get("argus") == "node" and b.get("name") == "argus-smoke":
        print(json.dumps(b)); break
PY
  BEACON_PID=$!
  chroot --userspec="$uid:$gid" "$MNT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME="$SD" LANG=C.UTF-8 \
    ARGUS_NODE_DIR="$SD" ARGUS_NODE_NAME=argus-smoke ARGUS_SECURE=1 ARGUS_PORT=50152 ARGUS_INTERNAL_PORT=50172 \
    ARGUS_BEACON_TARGET=127.0.0.1 ARGUS_THREADS=2 ARGUS_TRUST_LOOPBACK=0 \
    /bin/bash /opt/argus-node/argus-node-linux.sh >"$MNT$SD.log" 2>&1 &
  SMOKE_PID=$!
  ok=0
  for _ in $(seq 1 40); do
    if [ -s "$MNT$SD/pin" ] && (exec 3<>/dev/tcp/127.0.0.1/50152 && head -c 7 <&3 | grep -q '^ARGUS1 ') 2>/dev/null \
       && (exec 3<>/dev/tcp/127.0.0.1/50172) 2>/dev/null; then ok=1; break; fi
    kill -0 "$SMOKE_PID" 2>/dev/null || break
    sleep 1
  done
  wait "$BEACON_PID" 2>/dev/null || true
  kill -TERM "$SMOKE_PID" 2>/dev/null || true
  for _ in $(seq 1 10); do kill -0 "$SMOKE_PID" 2>/dev/null || break; sleep 1; done
  SMOKE_PID=""
  kill_chroot_procs
  echo "---- node log" >&2; cat "$MNT$SD.log" >&2 || true
  echo "---- beacon" >&2; cat "$MNT$SD.beacon" >&2 || true
  [ "$ok" = 1 ] || die "smoke test: gateway :50152 / rpc-server :50172 / PIN file did not come up"
  grep -q '"auth": 1' "$MNT$SD.beacon" || die "smoke test: no beacon with auth=1 received on UDP 50053"
  grep -q 'aarch64-' "$MNT$SD.beacon" || die "smoke test: beacon does not report a static aarch64 build"
  rm -rf "${MNT:?}$SD" "$MNT$SD.log" "$MNT$SD.beacon"
  log "smoke test OK"
fi

# ------------------------------------------------------------------ scrub + finish
log "scrubbing build leftovers"
if [ "$APT_USED" = 1 ]; then in_chroot apt-get clean; rm -rf "$MNT"/var/lib/apt/lists/*; fi
if [ -n "$RESOLV_BACKUP" ]; then
  rm -f "$MNT/etc/resolv.conf"
  if [ -e "$RESOLV_BACKUP.none" ]; then rm -f "$RESOLV_BACKUP.none"; else mv "$RESOLV_BACKUP" "$MNT/etc/resolv.conf"; fi
fi
if [ "$(cat "$MNT/etc/machine-id" 2>/dev/null || true)" != "$MACHINE_ID_BEFORE" ]; then
  log "machine-id was touched — restoring"; printf '%s' "$MACHINE_ID_BEFORE" >"$MNT/etc/machine-id"
  [ -n "$MACHINE_ID_BEFORE" ] && echo >>"$MNT/etc/machine-id"
fi
HOSTKEYS_AFTER="$(hostkeys)"
if [ "$HOSTKEYS_AFTER" != "$HOSTKEYS_BEFORE" ]; then
  log "SSH host keys appeared during the build — removing (regenerated on first boot)"
  for k in $HOSTKEYS_AFTER; do case " $HOSTKEYS_BEFORE " in *" $k "*) ;; *) rm -f "$MNT/etc/ssh/$k" ;; esac; done
fi
rm -f "$MNT/root/.bash_history"
ls -la "$MNT/opt/argus-node" "$MNT/boot/firmware/argus.conf" "$MNT/boot/firmware/ssh" >&2
cat "$MNT/opt/argus-node/BUILD-INFO" >&2
df -h "$MNT" >&2

for m in dev/pts dev proc sys; do umount "$MNT/$m"; done
fstrim -v "$MNT/boot/firmware" >&2 || true
fstrim -v "$MNT" >&2 || true
umount "$MNT/boot/firmware"; umount "$MNT"; rmdir "$MNT"; MNT=""
e2fsck -fy "${LOOP}p2" >&2 || [ $? -le 1 ] || die "final e2fsck failed"
losetup -d "$LOOP"; LOOP=""
log "done: $OUT ($(du -h --apparent-size "$OUT" | cut -f1), $(du -h "$OUT" | cut -f1) on disk)"
