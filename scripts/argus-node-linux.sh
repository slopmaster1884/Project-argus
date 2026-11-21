#!/usr/bin/env bash
# Argus Wi-Fi node for a Linux PC or Raspberry Pi.
#
# Downloads ggml rpc-server from llama.cpp b12008 (the same build as the Argus desktop app — the RPC
# protocol must match), runs `rpc-server -H 0.0.0.0 -p 50052` and broadcasts the Argus beacon every 2 s
# to UDP 50053:
#   {"argus":"node","v":1,"name":"<model>","port":50052,"ram_mb":N,"free_mb":N,"variant":"..."}
# The node then shows up in Argus → Cluster → "Найдено в сети" (button "Добавить").
#
# ⚠ rpc-server has NO password and NO encryption: closed home network only, never expose port 50052.
#
# ARGUS_SECURE=1 (opt-in «защищённый режим», docs/SECURITY.md): rpc-server listens on 127.0.0.1:50072 only and an
# auth gateway (python3, stdlib) takes port 50052. Argus connects only with the node token it got by pairing
# with the 6-digit PIN printed here (also in $DIR/pin). Needs Argus 0.3.5+; older Argus cannot use a secured node.
# Token: $DIR/token (delete it, or run with --reset-token, to unpair every PC).
#
# Usage:  bash argus-node-linux.sh            run in the foreground (Ctrl+C stops everything)
#         bash argus-node-linux.sh --systemd  install + start a systemd --user service (autostart)
#         bash argus-node-linux.sh --uninstall-systemd
#         bash argus-node-linux.sh --open-firewall   open TCP port for Argus in ufw/firewalld (asks sudo)
#         bash argus-node-linux.sh --reset-token     forget the secured-mode token (every PC has to pair again)
# Env:    ARGUS_PORT=50052 ARGUS_NODE_NAME="Pi 5" ARGUS_THREADS=4 ARGUS_CPU=1 (force CPU build on x64)
#         ARGUS_SECURE=1 (PIN + token auth gateway)  ARGUS_INTERNAL_PORT=50072 (rpc-server port behind the gateway)
#         ARGUS_RPC_BIN=/path/to/rpc-server (skip download)  ARGUS_BEACON_TARGET=192.168.1.10 (unicast
#         beacon to the PC when broadcast is filtered)  ARGUS_NODE_DIR=~/.local/share/argus-node
set -euo pipefail

LLAMA_REF="${LLAMA_REF:-b12008}"
PORT="${ARGUS_PORT:-50052}"
BEACON_PORT=50053
DIR="${ARGUS_NODE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/argus-node}"
THREADS="${ARGUS_THREADS:-$(nproc 2>/dev/null || echo 4)}"
SECURE="${ARGUS_SECURE:-0}"
INTERNAL_PORT="${ARGUS_INTERNAL_PORT:-50072}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_REF}"
mkdir -p "$DIR/cache"

log() { printf '[argus-node] %s\n' "$*" >&2; }
die() { log "ОШИБКА: $*"; exit 1; }

default_name() {
  local m=""
  [ -r /proc/device-tree/model ] && m="$(tr -d '\0' </proc/device-tree/model)"
  [ -z "$m" ] && [ -r /sys/class/dmi/id/product_name ] && m="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
  [ -z "$m" ] && m="$(hostname)"
  printf '%s' "$m"
}
NAME="${ARGUS_NODE_NAME:-$(default_name)}"

# ------------------------------------------------------------------ systemd helper
UNIT="$HOME/.config/systemd/user/argus-node.service"
if [ "${1:-}" = "--systemd" ]; then
  mkdir -p "$(dirname "$UNIT")"
  install -m 0755 "${BASH_SOURCE[0]}" "$DIR/argus-node-linux.sh"
  # keep the static aarch64 builds next to the installed copy (they are looked up relative to the script)
  for f in "$SCRIPT_DIR"/../android/app/src/main/jniLibs/arm64-v8a/librpc_server*.so; do [ -f "$f" ] && cp "$f" "$DIR/"; done
  cat >"$UNIT" <<UNIT_EOF
[Unit]
Description=Argus Wi-Fi node (llama.cpp ${LLAMA_REF} rpc-server + beacon)
After=network-online.target

[Service]
Environment=ARGUS_PORT=${PORT} ARGUS_NODE_NAME=${NAME// /\\x20} ARGUS_THREADS=${THREADS} ARGUS_SECURE=${SECURE}
ExecStart=/usr/bin/env bash ${DIR}/argus-node-linux.sh
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
UNIT_EOF
  systemctl --user daemon-reload
  systemctl --user enable --now argus-node.service
  log "сервис установлен: systemctl --user status argus-node  (для автозапуска без входа: sudo loginctl enable-linger $USER)"
  exit 0
fi
if [ "${1:-}" = "--uninstall-systemd" ]; then
  systemctl --user disable --now argus-node.service 2>/dev/null || true
  rm -f "$UNIT"; systemctl --user daemon-reload || true
  log "сервис удалён"; exit 0
fi
if [ "${1:-}" = "--reset-token" ]; then
  rm -f "$DIR/token" "$DIR/pin"; log "токен защищённого режима удалён — все ПК должны заново ввести PIN"; exit 0
fi
if [ "${1:-}" = "--open-firewall" ]; then
  if command -v ufw >/dev/null; then sudo ufw allow "${PORT}/tcp"
  elif command -v firewall-cmd >/dev/null; then sudo firewall-cmd --permanent --add-port="${PORT}/tcp" && sudo firewall-cmd --reload
  else log "ufw/firewalld не найдены — открывать нечего"; fi
  exit 0
fi

# ------------------------------------------------------------------ pick / download rpc-server
fetch() { # url dest
  if command -v curl >/dev/null; then curl -fL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null; then wget -O "$2" "$1"
  else die "нужен curl или wget"; fi
}

from_release() { # asset-suffix variant
  local tgz="llama-${LLAMA_REF}-bin-$1.tar.gz" out="$DIR/${LLAMA_REF}-$2"
  if [ ! -x "$out/ggml-rpc-server" ]; then
    log "скачиваю ${tgz} …"
    rm -rf "$out" && mkdir -p "$out"
    fetch "$REL/$tgz" "$DIR/$tgz"
    tar -xzf "$DIR/$tgz" -C "$out" --strip-components=1
    rm -f "$DIR/$tgz"
    [ -x "$out/ggml-rpc-server" ] || die "в архиве нет ggml-rpc-server"
  fi
  BIN="$out/ggml-rpc-server"; VARIANT="$2"
}

# Vulkan loader present? Works on Debian/Ubuntu, Fedora, Arch, openSUSE (not only the Debian lib path).
has_vulkan() {
  command -v vulkaninfo >/dev/null && vulkaninfo --summary >/dev/null 2>&1 && return 0
  command -v ldconfig >/dev/null && ldconfig -p 2>/dev/null | grep -q 'libvulkan\.so\.1' && return 0
  /sbin/ldconfig -p 2>/dev/null | grep -q 'libvulkan\.so\.1' && return 0
  local f; for f in /usr/lib/x86_64-linux-gnu/libvulkan.so.1 /usr/lib64/libvulkan.so.1 /usr/lib/libvulkan.so.1; do
    [ -e "$f" ] && return 0; done
  return 1
}

BIN="${ARGUS_RPC_BIN:-}"; VARIANT="${ARGUS_VARIANT:-custom}"
if [ -z "$BIN" ]; then
  case "$(uname -m)" in
    x86_64|amd64)
      if [ "${ARGUS_CPU:-0}" != "1" ] && has_vulkan; then
        from_release ubuntu-vulkan-x64 x64-vulkan
      else
        from_release ubuntu-x64 x64-cpu
      fi ;;
    aarch64|arm64)
      # Our static musl builds (same as Argus Node on Android) run on any arm64 Linux, incl. Raspberry Pi OS.
      feats="$(grep -m1 -i '^features' /proc/cpuinfo 2>/dev/null || true)"
      pick=librpc_server.so; VARIANT=aarch64-baseline
      case " $feats " in *" i8mm "*) pick=librpc_server_i8mm.so; VARIANT=aarch64-i8mm;; *" asimddp "*) pick=librpc_server_dotprod.so; VARIANT=aarch64-dotprod;; esac
      for d in "$SCRIPT_DIR" "$SCRIPT_DIR/../android/app/src/main/jniLibs/arm64-v8a" "$DIR"; do
        if [ -f "$d/$pick" ]; then cp "$d/$pick" "$DIR/rpc-server-$VARIANT"; chmod +x "$DIR/rpc-server-$VARIANT"; BIN="$DIR/rpc-server-$VARIANT"; break; fi
        if [ -f "$d/librpc_server.so" ]; then cp "$d/librpc_server.so" "$DIR/rpc-server-aarch64-baseline"; chmod +x "$DIR/rpc-server-aarch64-baseline"; BIN="$DIR/rpc-server-aarch64-baseline"; VARIANT=aarch64-baseline; break; fi
      done
      if [ -z "$BIN" ]; then
        log "статическая сборка не найдена рядом со скриптом — беру официальный ubuntu-arm64 (нужен glibc ≥ 2.35)"
        from_release ubuntu-arm64 aarch64
      fi ;;
    *) die "архитектура $(uname -m) не поддерживается: соберите rpc-server ${LLAMA_REF} сами (-DGGML_RPC=ON) и задайте ARGUS_RPC_BIN" ;;
  esac
fi
[ -x "$BIN" ] || die "rpc-server не найден: $BIN"

# ------------------------------------------------------------------ beacon
mem_kb() { awk -v k="$1:" '$1==k {print $2}' /proc/meminfo; }
PIDFILE="$DIR/rpc.pid"

beacon_python() {
  ARGUS_NAME="$NAME" ARGUS_VARIANT="$VARIANT" ARGUS_PORT="$PORT" ARGUS_PIDFILE="$PIDFILE" ARGUS_SECURE="$SECURE" \
  ARGUS_BEACON_PORT="$BEACON_PORT" ARGUS_TARGET="${ARGUS_BEACON_TARGET:-}" python3 - <<'PY'
import json, os, socket, time
name, variant = os.environ["ARGUS_NAME"], os.environ["ARGUS_VARIANT"]
port, bport, pidfile = int(os.environ["ARGUS_PORT"]), int(os.environ["ARGUS_BEACON_PORT"]), os.environ["ARGUS_PIDFILE"]
targets = ["255.255.255.255"] + [t for t in os.environ.get("ARGUS_TARGET", "").split(",") if t]
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
def mem():
    m = {}
    with open("/proc/meminfo") as f:
        for l in f:
            k, v = l.split(":", 1); m[k] = int(v.split()[0])
    return m.get("MemTotal", 0) // 1024, m.get("MemAvailable", 0) // 1024
def alive():
    try:
        os.kill(int(open(pidfile).read().strip()), 0); return True
    except Exception:
        return False
while True:
    if alive():  # no beacon while rpc-server is down -> Argus marks the node OFFLINE after 10 s
        total, free = mem()
        b = {"argus": "node", "v": 1, "name": name, "port": port, "ram_mb": total, "free_mb": free, "variant": variant}
        if os.environ.get("ARGUS_SECURE") == "1": b["auth"] = 1   # secured RPC: Argus asks for the PIN
        msg = json.dumps(b).encode()
        for t in targets:
            try: s.sendto(msg, (t, bport))
            except OSError: pass
    time.sleep(2)
PY
}

beacon_socat() {
  while true; do
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      msg=$(printf '{"argus":"node","v":1,"name":"%s","port":%s,"ram_mb":%s,"free_mb":%s,"variant":"%s"}' \
        "${NAME//\"/}" "$PORT" "$(( $(mem_kb MemTotal) / 1024 ))" "$(( $(mem_kb MemAvailable) / 1024 ))" "$VARIANT")
      printf '%s' "$msg" | socat - "UDP-DATAGRAM:255.255.255.255:${BEACON_PORT},broadcast" 2>/dev/null || true
      for t in ${ARGUS_BEACON_TARGET//,/ }; do printf '%s' "$msg" | socat - "UDP-DATAGRAM:${t}:${BEACON_PORT}" 2>/dev/null || true; done
    fi
    sleep 2
  done
}

# ------------------------------------------------------------------ secured mode: auth gateway (ARGUS_SECURE=1)
GW_PID=""
RPC_HOST=0.0.0.0; RPC_PORT="$PORT"
write_gateway() {
  cat >"$DIR/argus-gateway.py" <<'GW_EOF'
# Argus secured-RPC gateway (docs/SECURITY.md). python3 stdlib only.
# Listens on 0.0.0.0:$ARGUS_PORT, authenticates the client (HMAC challenge-response with the node token,
# or SPAKE2 pairing with the 6-digit PIN) and then pipes raw bytes to rpc-server on $ARGUS_UPSTREAM.
import hashlib, hmac, os, secrets, socket, sys, threading, time

PORT = int(os.environ.get("ARGUS_PORT", "50052"))
UP_HOST, UP_PORT = os.environ.get("ARGUS_UPSTREAM", "127.0.0.1:50072").rsplit(":", 1)
TOKEN_FILE = os.environ["ARGUS_TOKEN_FILE"]
PIN_FILE = os.environ.get("ARGUS_PIN_FILE", "")
BIND = os.environ.get("ARGUS_BIND", "0.0.0.0")
TRUST_LOOPBACK = os.environ.get("ARGUS_TRUST_LOOPBACK", "1") == "1"

P = int("FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF", 16)
Q = (P - 1) // 2
def _sq(label):
    h = int.from_bytes(hashlib.sha256(label).digest(), "big"); return h * h % P
M, N = _sq(b"argus-spake2-M"), _sq(b"argus-spake2-N")
MAX_FAILS = 5

def log(msg): print("[argus-gw] " + msg, file=sys.stderr, flush=True)
def mac(key, *parts): return hmac.new(key, b"".join(parts), hashlib.sha256).digest()
def eb(x): return x.to_bytes(256, "big")

def load_token():
    try:
        t = bytes.fromhex(open(TOKEN_FILE).read().strip())
        if len(t) == 32: return t
    except (OSError, ValueError):
        pass
    t = secrets.token_bytes(32)
    old = os.umask(0o077)
    try:
        with open(TOKEN_FILE, "w") as f: f.write(t.hex() + "\n")
    finally:
        os.umask(old)
    log("new node token created: " + TOKEN_FILE)
    return t

TOKEN = load_token()
lock = threading.Lock()
state = {"pin": None, "fails": 0}

def new_pin():
    state["pin"], state["fails"] = "%06d" % secrets.randbelow(10 ** 6), 0
    pin = state["pin"]
    if PIN_FILE:
        old = os.umask(0o077)
        try:
            with open(PIN_FILE, "w") as f: f.write(pin + "\n")
        except OSError: pass
        finally: os.umask(old)
    log("=" * 44)
    log("  PIN для сопряжения с Argus:  %s %s" % (pin[:3], pin[3:]))
    log("  (Argus → «Найдено в сети» → «Добавить» → PIN)")
    log("=" * 44)

def readline(conn, buf):
    while b"\n" not in buf:
        if len(buf) > 1200: raise ValueError("line too long")
        if buf[:1] not in (b"", b"A", b"P"): raise ValueError("не клиент Argus с PIN (старый Argus?)")
        d = conn.recv(1300)
        if not d: raise ConnectionError("closed")
        buf += d
    line, rest = buf.split(b"\n", 1)
    return line.decode("ascii").strip(), rest

def pump(src, dst):
    try:
        while True:
            d = src.recv(65536)
            if not d: break
            dst.sendall(d)
    except OSError:
        pass
    for s, how in ((dst, socket.SHUT_WR), (src, socket.SHUT_RD)):
        try: s.shutdown(how)
        except OSError: pass

def bridge(conn, rest):
    up = socket.create_connection((UP_HOST, int(UP_PORT)), timeout=10)
    up.settimeout(None); conn.settimeout(None)
    for s in (up, conn): s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    if rest: up.sendall(rest)
    t = threading.Thread(target=pump, args=(up, conn), daemon=True); t.start()
    pump(conn, up); t.join()
    up.close()

def pair(conn, nonce, x_hex, rest):
    x = int(x_hex, 16)
    if not (1 < x < P - 1 and pow(x, Q, P) == 1): conn.sendall(b"ERR bad\n"); return
    with lock:
        if state["pin"] is None: new_pin()
        pin = state["pin"]
    w = int.from_bytes(mac(b"argus-pin", pin.encode()), "big") % Q
    y = secrets.randbelow(Q)
    Y = pow(2, y, P) * pow(N, w, P) % P
    conn.sendall(b"PAIRB " + eb(Y).hex().encode() + b"\n")
    line, rest = readline(conn, rest)
    z = pow(x * pow(pow(M, w, P), P - 2, P) % P, y, P)
    k = hashlib.sha256(b"argus-spake2|" + nonce + eb(x) + eb(Y) + eb(z) + w.to_bytes(32, "big")).digest()
    c = line[6:] if line.startswith("PAIRC ") else ""
    try: ok = hmac.compare_digest(bytes.fromhex(c), mac(k, b"c"))
    except ValueError: ok = False
    if not ok:
        with lock:
            state["fails"] += 1
            log("неверный PIN (%d/%d)" % (state["fails"], MAX_FAILS))
            if state["fails"] >= MAX_FAILS: log("слишком много попыток — новый PIN"); new_pin()
        time.sleep(1)
        conn.sendall(b"ERR pin\n"); return
    pad = mac(k, b"k")
    enc = bytes(a ^ b for a, b in zip(TOKEN, pad))
    conn.sendall(b"PAIROK " + enc.hex().encode() + b" " + mac(k, b"s", enc).hex().encode() + b"\n")
    with lock: state["fails"] = 0
    log("сопряжение выполнено: %s" % conn.getpeername()[0])

def handle(conn, addr):
    try:
        if TRUST_LOOPBACK and addr[0].startswith("127."):           # loopback (adb forward / same machine): internal port is local anyway
            bridge(conn, b""); return
        conn.settimeout(10)
        nonce = secrets.token_bytes(16)
        conn.sendall(b"ARGUS1 " + nonce.hex().encode() + b"\n")
        line, rest = readline(conn, b"")
        if line.startswith("AUTH "):
            try: got = bytes.fromhex(line[5:])
            except ValueError: got = b""
            want = mac(TOKEN, b"argus-auth|", nonce)
            if not hmac.compare_digest(got, want):
                log("отклонено (неверный ключ): %s" % addr[0]); time.sleep(0.5)
                conn.sendall(b"ERR auth\n"); return
            conn.sendall(b"OK " + mac(TOKEN, b"argus-srv|", nonce, got).hex().encode() + b"\n")
            bridge(conn, rest)
        elif line.startswith("PAIR "):
            pair(conn, nonce, line[5:], rest)
        else:
            conn.sendall(b"ERR proto\n")
    except (OSError, ValueError, ConnectionError) as e:
        if not isinstance(e, ConnectionError): log("%s: %s" % (addr[0], e))
    finally:
        try: conn.close()
        except OSError: pass

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((BIND, PORT)); srv.listen(16)
    log("защищённый режим: шлюз %s:%d → rpc-server %s:%s" % (BIND, PORT, UP_HOST, UP_PORT))
    with lock: new_pin()
    while True:
        try:
            conn, addr = srv.accept()
            threading.Thread(target=handle, args=(conn, addr), daemon=True).start()
        except OSError as e:          # EMFILE etc.: keep serving
            log("accept: %s" % e); time.sleep(0.2)

if __name__ == "__main__":
    main()
GW_EOF
}
if [ "$SECURE" = "1" ]; then
  command -v python3 >/dev/null || die "ARGUS_SECURE=1 нужен python3"
  [ "$INTERNAL_PORT" != "$PORT" ] || die "ARGUS_INTERNAL_PORT должен отличаться от ARGUS_PORT"
  write_gateway
  RPC_HOST=127.0.0.1; RPC_PORT="$INTERNAL_PORT"
  ARGUS_PORT="$PORT" ARGUS_UPSTREAM="127.0.0.1:${INTERNAL_PORT}" ARGUS_TOKEN_FILE="$DIR/token" ARGUS_PIN_FILE="$DIR/pin" \
    python3 "$DIR/argus-gateway.py" & GW_PID=$!
fi

BEACON_PID=""
cleanup() {
  [ -n "$BEACON_PID" ] && kill "$BEACON_PID" 2>/dev/null || true
  [ -n "$GW_PID" ] && kill "$GW_PID" 2>/dev/null || true
  [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
}
trap 'cleanup; exit 0' INT TERM
trap cleanup EXIT

if command -v python3 >/dev/null; then beacon_python & BEACON_PID=$!
elif command -v socat >/dev/null; then beacon_socat & BEACON_PID=$!
else log "нет python3 и socat — маяк выключен; добавьте ноду в Argus вручную: <IP>:${PORT}"; fi

# ------------------------------------------------------------------ firewall self-check (issue #3)
# Symptom when blocked: node appears in "Найдено в сети" (UDP beacon goes OUT fine), but after "Добавить"
# it goes OFFLINE, because the PC cannot open TCP ${PORT} on this machine.
firewall_check() {
  if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
    if ! ufw status 2>/dev/null | grep -Eq "^${PORT}(/tcp)?[[:space:]]+ALLOW"; then
      log "⚠ включён файрвол ufw и порт ${PORT}/tcp закрыт — Argus увидит ноду, но не сможет подключиться."
      log "   Откройте его одной командой:  sudo ufw allow ${PORT}/tcp"
    fi
  elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
    if ! firewall-cmd --list-ports 2>/dev/null | grep -qw "${PORT}/tcp"; then
      log "⚠ включён firewalld и порт ${PORT}/tcp закрыт — Argus увидит ноду, но не сможет подключиться."
      log "   Откройте его:  sudo firewall-cmd --permanent --add-port=${PORT}/tcp && sudo firewall-cmd --reload"
    fi
  fi
}
firewall_check || true

IPS="$(hostname -I 2>/dev/null || true)"
log "нода «${NAME}» · ${VARIANT} · ${THREADS} потоков · порт ${PORT} · IP: ${IPS:-?}"
if [ "$SECURE" = "1" ]; then
  log "🔒 защищённый режим: rpc-server на 127.0.0.1:${INTERNAL_PORT}, вход на :${PORT} только с ключом (PIN выше, или: cat $DIR/pin)"
  log "   трафик НЕ шифруется — это защита от чужих устройств в сети, а не замена VPN/TLS (docs/SECURITY.md)"
else
  log "⚠ без пароля и шифрования — только закрытая домашняя сеть (защищённый режим: ARGUS_SECURE=1)"
fi

# ------------------------------------------------------------------ rpc-server, restarted if it dies
while true; do
  LLAMA_CACHE="$DIR/cache" LD_LIBRARY_PATH="$(dirname "$BIN")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$BIN" -H "$RPC_HOST" -p "$RPC_PORT" -t "$THREADS" -c &
  echo $! >"$PIDFILE"
  wait "$(cat "$PIDFILE")" && code=0 || code=$?
  rm -f "$PIDFILE"
  if [ -n "$GW_PID" ] && ! kill -0 "$GW_PID" 2>/dev/null; then
    log "шлюз защищённого режима упал — перезапуск"
    ARGUS_PORT="$PORT" ARGUS_UPSTREAM="127.0.0.1:${INTERNAL_PORT}" ARGUS_TOKEN_FILE="$DIR/token" ARGUS_PIN_FILE="$DIR/pin" \
      python3 "$DIR/argus-gateway.py" & GW_PID=$!
  fi
  log "rpc-server завершился (код $code) — перезапуск через 3 с"
  sleep 3
done
