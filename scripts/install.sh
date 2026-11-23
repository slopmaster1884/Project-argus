#!/usr/bin/env bash
# Argus node — one-command installer for Linux (PC, laptop, Raspberry Pi).
#
#   curl -fsSL https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/install.sh | bash
#
# What it does (nothing is installed system-wide without asking):
#   1. checks the CPU architecture, the distro and the tools it needs (curl/wget, tar, python3 or socat);
#      if something is missing it prints the exact command for your package manager and asks before sudo;
#   2. downloads scripts/argus-node-linux.sh from the same repo ref into ~/.local/share/argus-node/;
#   3. offers to open TCP port 50052 in ufw/firewalld (argus-node-linux.sh --open-firewall);
#   4. installs a systemd --user service (argus-node-linux.sh --systemd), or runs in the foreground;
#   5. prints this machine's IP address(es) and what to click in Argus.
#
# Options:  --foreground   run in this terminal instead of installing a service (Ctrl+C stops it)
#           --uninstall    stop and remove the service and the downloaded files
#           --yes, -y      answer "yes" to every question (same as ARGUS_YES=1)
#           --no-firewall  do not touch the firewall
#           --lang ru|en   message language (default: Russian if LANG starts with "ru", else English)
#           --help
# Env:      ARGUS_REF=main (git branch/tag to download from)  ARGUS_YES=1  ARGUS_LANG=ru|en
#           ARGUS_REPO=slopmaster1884/Project-argus  ARGUS_NODE_DIR=~/.local/share/argus-node
#           ARGUS_LOCAL_SCRIPT=/path/argus-node-linux.sh (use a local copy, skip the download)
#           Everything else (ARGUS_PORT, ARGUS_NODE_NAME, ARGUS_THREADS, ARGUS_CPU, ARGUS_BEACON_TARGET)
#           is passed through to argus-node-linux.sh.
#
# ⚠ rpc-server has NO password and NO encryption: home network only, never forward port 50052.
#
# The whole script lives in main() and is called on the last line, so a half-downloaded
# `curl | bash` never runs a half script.

set -euo pipefail

ARGUS_REPO="${ARGUS_REPO:-slopmaster1884/Project-argus}"
ARGUS_REF="${ARGUS_REF:-main}"
RAW="https://raw.githubusercontent.com/${ARGUS_REPO}/${ARGUS_REF}"
DIR="${ARGUS_NODE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/argus-node}"
SRC_DIR="$DIR/src"                     # the downloaded copy; --systemd installs it into $DIR itself
NODE_SH="$SRC_DIR/argus-node-linux.sh"
PORT="${ARGUS_PORT:-50052}"
YES="${ARGUS_YES:-0}"
MODE="service"                         # service | foreground | uninstall
FIREWALL=1
UI_LANG="${ARGUS_LANG:-}"

# ------------------------------------------------------------------ text helpers
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; N=$'\033[0m'
else B=""; G=""; Y=""; R=""; C=""; N=""; fi

is_ru() { [ "$UI_LANG" = "ru" ]; }
# msg "русский текст" "english text"
msg()  { if is_ru; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
info() { printf '%s' "${C}==>${N} "; msg "$@"; }
ok()   { printf '%s' "${G} ✔ ${N} "; msg "$@"; }
warn() { printf '%s' "${Y} ⚠ ${N} "; msg "$@"; }
fail() { printf '%s' "${R} ✘ ${N} " >&2; msg "$@" >&2; exit 1; }

# ask "вопрос" "question" default(y|n)  -> 0 = yes. Reads the answer from the terminal even under `curl | bash`.
ask() {
  local def="$3" ans="" hint="[y/N]"
  [ "$def" = "y" ] && hint="[Y/n]"
  if [ "$YES" = "1" ]; then return 0; fi
  if ! { : </dev/tty; } 2>/dev/null; then
    [ "$def" = "y" ]; return
  fi
  printf '%s' "${B}?${N} "
  if is_ru; then printf '%s %s ' "$1" "$hint"; else printf '%s %s ' "$2" "$hint"; fi
  read -r ans </dev/tty || ans=""
  [ -z "$ans" ] && ans="$def"
  case "$ans" in [yYдД]*) return 0 ;; *) return 1 ;; esac
}

usage() {
  if is_ru; then cat <<EOF_RU
Установка ноды Argus на Linux:
  curl -fsSL ${RAW}/scripts/install.sh | bash
  curl -fsSL ${RAW}/scripts/install.sh | bash -s -- [параметры]

  --foreground   запустить в этом окне, без автозапуска (остановка: Ctrl+C)
  --uninstall    остановить и удалить ноду
  --yes, -y      отвечать «да» на все вопросы (то же, что ARGUS_YES=1)
  --no-firewall  не трогать файрвол
  --lang ru|en   язык сообщений

Подробно: https://github.com/${ARGUS_REPO}/blob/main/docs/LINUX.md
EOF_RU
  else cat <<EOF_EN
Argus node installer for Linux:
  curl -fsSL ${RAW}/scripts/install.sh | bash
  curl -fsSL ${RAW}/scripts/install.sh | bash -s -- [options]

  --foreground   run in this terminal, no autostart (stop with Ctrl+C)
  --uninstall    stop and remove the node
  --yes, -y      answer "yes" to every question (same as ARGUS_YES=1)
  --no-firewall  do not touch the firewall
  --lang ru|en   message language

Details: https://github.com/${ARGUS_REPO}/blob/main/docs/LINUX.en.md
EOF_EN
  fi
}

# run a command with the terminal as stdin when there is one (sudo needs it for the password under `curl | bash`)
with_tty() {
  if { : </dev/tty; } 2>/dev/null; then "$@" </dev/tty; else "$@"; fi
}

# ------------------------------------------------------------------ environment checks
PM=""            # apt | dnf | pacman | zypper | ""
DISTRO="Linux"

detect_distro() {
  local id="" like="" pretty=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    id="$(. /etc/os-release && printf '%s' "${ID:-}")"
    # shellcheck disable=SC1091
    like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
    # shellcheck disable=SC1091
    pretty="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-}")"
  fi
  DISTRO="${pretty:-${id:-Linux}}"
  case " $id $like " in
    *" debian "*|*" ubuntu "*|*" raspbian "*) PM=apt ;;
    *" fedora "*|*" rhel "*|*" centos "*)    PM=dnf ;;
    *" arch "*|*" manjaro "*)                PM=pacman ;;
    *" suse "*|*" opensuse "*|*" sles "*)    PM=zypper ;;
  esac
  if [ -z "$PM" ]; then
    if command -v apt-get >/dev/null 2>&1; then PM=apt
    elif command -v dnf >/dev/null 2>&1; then PM=dnf
    elif command -v pacman >/dev/null 2>&1; then PM=pacman
    elif command -v zypper >/dev/null 2>&1; then PM=zypper; fi
  fi
}

check_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  ARCH=x86_64 ;;
    aarch64|arm64) ARCH=aarch64 ;;
    armv7l|armv6l)
      fail "Это 32-битная система ($(uname -m)). Нужна 64-битная: на Raspberry Pi поставьте Raspberry Pi OS (64-bit)." \
           "This is a 32-bit system ($(uname -m)). A 64-bit OS is required: on a Raspberry Pi install Raspberry Pi OS (64-bit)." ;;
    *)
      fail "Архитектура $(uname -m) не поддерживается (нужен x86_64 или aarch64)." \
           "Architecture $(uname -m) is not supported (x86_64 or aarch64 required)." ;;
  esac
  [ "$(uname -s)" = "Linux" ] || fail "Этот установщик только для Linux. Для Windows: scripts/argus-node-windows.cmd" \
                                      "This installer is for Linux only. For Windows: scripts/argus-node-windows.cmd"
}

# package names per manager: pkg_for <tool>
pkg_for() {
  case "$PM:$1" in
    pacman:python3) echo python ;;
    *:python3)      echo python3 ;;
    *)              echo "$1" ;;
  esac
}

install_cmd() { # packages...
  case "$PM" in
    apt)    echo "sudo apt-get update && sudo apt-get install -y $*" ;;
    dnf)    echo "sudo dnf install -y $*" ;;
    pacman) echo "sudo pacman -S --needed --noconfirm $*" ;;
    zypper) echo "sudo zypper --non-interactive install $*" ;;
    *)      echo "" ;;
  esac
}

check_deps() {
  local missing=() pkgs=() t
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || missing+=(curl)
  command -v tar  >/dev/null 2>&1 || missing+=(tar)
  command -v gzip >/dev/null 2>&1 || missing+=(gzip)
  command -v python3 >/dev/null 2>&1 || command -v socat >/dev/null 2>&1 || missing+=(python3)
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "Все нужные программы на месте." "All required tools are present."
    return 0
  fi
  for t in "${missing[@]}"; do pkgs+=("$(pkg_for "$t")"); done
  local cmd; cmd="$(install_cmd "${pkgs[@]}")"
  warn "Не хватает программ: ${pkgs[*]}" "Missing tools: ${pkgs[*]}"
  if [ -z "$cmd" ]; then
    fail "Не знаю менеджер пакетов вашей системы ($DISTRO). Установите вручную: ${pkgs[*]} — и запустите установщик снова." \
         "Unknown package manager on $DISTRO. Install these yourself: ${pkgs[*]} — then run the installer again."
  fi
  msg "Команда для установки:" "Command to install them:"
  printf '\n    %s\n\n' "${B}${cmd}${N}"
  if [ "$(id -u)" -eq 0 ]; then cmd="${cmd//sudo /}"; fi
  if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    fail "sudo не найден. Выполните команду выше от root (su -) и запустите установщик снова." \
         "sudo not found. Run the command above as root (su -) and start the installer again."
  fi
  if ask "Выполнить её сейчас? sudo спросит ВАШ пароль от компьютера (символы не видны — это нормально)." \
         "Run it now? sudo will ask for YOUR computer password (typing is invisible — that's normal)." n; then
    with_tty bash -c "$cmd" || fail "Установка не удалась. Выполните команду выше вручную." \
                                                              "Install failed. Run the command above manually."
    check_deps
  else
    fail "Выполните команду выше и запустите установщик снова." "Run the command above, then start the installer again."
  fi
}

# ------------------------------------------------------------------ download
fetch() { # url dest
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 -o "$2" "$1"
  else wget -q -O "$2" "$1"; fi
}

download_node_script() {
  mkdir -p "$SRC_DIR"
  local tmp="$NODE_SH.part"
  if [ -n "${ARGUS_LOCAL_SCRIPT:-}" ]; then
    info "Беру локальный скрипт: $ARGUS_LOCAL_SCRIPT" "Using local script: $ARGUS_LOCAL_SCRIPT"
    cp "$ARGUS_LOCAL_SCRIPT" "$tmp"
  else
    info "Скачиваю argus-node-linux.sh ($ARGUS_REF)…" "Downloading argus-node-linux.sh ($ARGUS_REF)…"
    fetch "$RAW/scripts/argus-node-linux.sh" "$tmp" \
      || fail "Не удалось скачать $RAW/scripts/argus-node-linux.sh — проверьте интернет." \
              "Could not download $RAW/scripts/argus-node-linux.sh — check your internet connection."
  fi
  # sanity: non-empty, a bash script, parses, and really is the Argus node script
  [ -s "$tmp" ] || fail "Скачанный файл пустой." "The downloaded file is empty."
  head -n 1 "$tmp" | grep -q '^#!.*bash' || fail "Скачанный файл не похож на bash-скрипт (может, страница ошибки?)." \
                                                 "The downloaded file is not a bash script (an error page?)."
  bash -n "$tmp" || fail "Скачанный скрипт повреждён (bash -n)." "The downloaded script is corrupted (bash -n)."
  grep -q '"argus":"node"' "$tmp" || fail "Это не скрипт ноды Argus." "This is not the Argus node script."
  mv "$tmp" "$NODE_SH"
  chmod 0755 "$NODE_SH"
  ok "Скрипт ноды: $NODE_SH" "Node script: $NODE_SH"

  # aarch64 (Raspberry Pi etc.): our static rpc-server builds, the same as in the Argus Node Android app.
  # argus-node-linux.sh looks for them in its own folder and in $DIR.
  if [ "$ARCH" = "aarch64" ] && [ -z "${ARGUS_LOCAL_SCRIPT:-}" ]; then
    local so
    for so in librpc_server.so librpc_server_dotprod.so librpc_server_i8mm.so; do
      [ -s "$DIR/$so" ] && continue
      if fetch "$RAW/android/app/src/main/jniLibs/arm64-v8a/$so" "$DIR/$so.part" && [ -s "$DIR/$so.part" ]; then
        mv "$DIR/$so.part" "$DIR/$so"
      else
        rm -f "$DIR/$so.part"
        warn "Не скачался $so — скрипт возьмёт официальную сборку llama.cpp." \
             "Could not download $so — the script will use the official llama.cpp build."
      fi
    done
  fi
}

# ------------------------------------------------------------------ firewall
firewall_active() { # prints ufw | firewalld | nothing
  if command -v ufw >/dev/null 2>&1; then
    if systemctl is-active --quiet ufw 2>/dev/null && grep -qs '^ENABLED=yes' /etc/ufw/ufw.conf; then echo ufw; return; fi
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then echo firewalld; fi
}

maybe_open_firewall() {
  [ "$FIREWALL" = "1" ] || return 0
  local fw; fw="$(firewall_active)"
  if [ -z "$fw" ]; then
    ok "Файрвол не включён — порт $PORT открывать не нужно." "No active firewall — nothing to open for port $PORT."
    return 0
  fi
  if [ "$fw" = "firewalld" ] && firewall-cmd --list-ports 2>/dev/null | grep -qw "${PORT}/tcp"; then
    ok "Порт $PORT/tcp уже открыт в firewalld." "Port $PORT/tcp is already open in firewalld."
    return 0
  fi
  warn "Включён файрвол ($fw). Если не открыть порт $PORT/tcp, Argus увидит ноду, но не сможет к ней подключиться (OFFLINE)." \
       "A firewall is active ($fw). Unless port $PORT/tcp is open, Argus will see the node but cannot connect (OFFLINE)."
  if ask "Открыть порт $PORT/tcp? (нужен sudo)" "Open port $PORT/tcp? (needs sudo)" y; then
    if ARGUS_PORT="$PORT" ARGUS_NODE_DIR="$DIR" with_tty bash "$NODE_SH" --open-firewall; then
      ok "Порт $PORT/tcp открыт." "Port $PORT/tcp is open."
    else
      warn "Не получилось. Откройте вручную: bash $NODE_SH --open-firewall" \
           "That failed. Do it manually: bash $NODE_SH --open-firewall"
    fi
  else
    msg "Пропускаю. Открыть позже: bash $NODE_SH --open-firewall" "Skipped. To open it later: bash $NODE_SH --open-firewall"
  fi
}

# ------------------------------------------------------------------ service / foreground
have_user_systemd() {
  command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

port_listening() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${PORT}\$" && return 0
  fi
  (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null
}

DROPIN_DIR="$HOME/.config/systemd/user/argus-node.service.d"

# argus-node-linux.sh --systemd only writes ARGUS_PORT/NODE_NAME/THREADS into the unit; keep the other
# settings the user passed to the installer in a drop-in so the service sees them too.
write_dropin() {
  local v line="" q
  for v in ARGUS_BEACON_TARGET ARGUS_CPU ARGUS_RPC_BIN ARGUS_VARIANT; do
    if [ -n "${!v:-}" ]; then
      q="${!v//\\/\\\\}"; q="${q//\"/\\\"}"
      line+=" \"$v=$q\""
    fi
  done
  rm -f "$DROPIN_DIR/installer.conf"
  [ -n "$line" ] || return 0
  mkdir -p "$DROPIN_DIR"
  printf '[Service]\nEnvironment=%s\n' "${line# }" >"$DROPIN_DIR/installer.conf"
}

install_service() {
  info "Ставлю автозапуск (systemd --user)…" "Installing autostart (systemd --user)…"
  write_dropin
  ARGUS_NODE_DIR="$DIR" bash "$NODE_SH" --systemd \
    || fail "Не удалось создать сервис. Попробуйте: bash $NODE_SH" "Could not create the service. Try: bash $NODE_SH"
  info "Нода запускается. В первый раз она скачивает llama.cpp (~25–40 МБ), подождите…" \
       "The node is starting. The first time it downloads llama.cpp (~25–40 MB), please wait…"
  local i
  for i in $(seq 1 90); do
    if port_listening; then ok "Нода работает (порт $PORT)." "The node is running (port $PORT)."; break; fi
    if ! systemctl --user is-active --quiet argus-node.service; then
      [ "$i" -gt 5 ] && break
    fi
    printf '.'; sleep 2
  done
  echo
  if ! port_listening; then
    warn "Нода ещё не слушает порт $PORT. Посмотрите журнал:" "The node is not listening on port $PORT yet. Check the log:"
    printf '    journalctl --user -u argus-node -n 30 --no-pager\n'
    journalctl --user -u argus-node -n 15 --no-pager 2>/dev/null || true
  fi
  if command -v loginctl >/dev/null 2>&1 && [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || echo no)" != "yes" ]; then
    msg "Сейчас нода запускается, когда вы входите в систему." "Right now the node starts when you log in."
    if ask "Запускать её сразу при включении компьютера, без входа? (sudo loginctl enable-linger)" \
           "Start it right at boot, without logging in? (sudo loginctl enable-linger)" n; then
      local s="sudo"; [ "$(id -u)" -eq 0 ] && s=""
      with_tty $s loginctl enable-linger "$(id -un)" \
        || warn "Не получилось. Позже: sudo loginctl enable-linger $(id -un)" "Failed. Later: sudo loginctl enable-linger $(id -un)"
    fi
  fi
}

local_ips() {
  local out=""
  if command -v ip >/dev/null 2>&1; then
    out="$(ip -4 -o addr show scope global 2>/dev/null \
      | awk '$2 !~ /^(docker|br-|veth|virbr|lxc|tun|tap|wg|zt|tailscale)/ {split($4,a,"/"); print a[1] "  (" $2 ")"}')"
  fi
  if [ -z "$out" ] && command -v hostname >/dev/null 2>&1; then
    out="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' || true)"
  fi
  printf '%s' "$out"
}

banner() {
  local ips first line
  ips="$(local_ips)"
  first="$(printf '%s\n' "$ips" | head -n 1 | awk '{print $1}')"
  echo
  printf '%s\n' "${G}${B}╔══════════════════════════════════════════════════════════════╗${N}"
  if is_ru; then
    printf '%s\n' "${G}${B}   ГОТОВО! Этот компьютер — нода Argus.${N}"
  else
    printf '%s\n' "${G}${B}   DONE! This computer is now an Argus node.${N}"
  fi
  printf '%s\n' "${G}${B}╚══════════════════════════════════════════════════════════════╝${N}"
  echo
  msg "IP-адрес этого компьютера:" "This computer's IP address:"
  if [ -n "$ips" ]; then
    while IFS= read -r line; do printf '      %s\n' "${B}${line}${N}"; done <<<"$ips"
  else
    printf '      %s\n' "?"
  fi
  echo
  msg "Теперь на ГЛАВНОМ компьютере (где установлен Argus):" "Now, on the MAIN computer (where Argus is installed):"
  msg "  1. Откройте Argus → вкладка «Cluster»." "  1. Open Argus → the \"Cluster\" tab."
  msg "  2. В списке «Найдено в сети» найдите этот компьютер и нажмите «Добавить»." \
      "  2. In \"Найдено в сети\" (Found on network) find this computer and click \"Добавить\" (Add)."
  msg "  3. Нет в списке? Нажмите «Добавить ноду по IP» и введите:" \
      "  3. Not in the list? Click \"Добавить ноду по IP\" (Add node by IP) and type:"
  printf '\n         %s\n\n' "${B}${first:-<IP>}:${PORT}${N}"
  msg "Оба компьютера должны быть в одной домашней Wi-Fi сети (не гостевой)." \
      "Both computers must be on the same home Wi-Fi network (not a guest network)."
  warn "У ноды нет пароля: только домашняя сеть, не открывайте порт $PORT в интернет." \
       "The node has no password: home network only, never expose port $PORT to the internet."
  echo
}

after_service_help() {
  msg "Полезные команды:" "Useful commands:"
  printf '    systemctl --user status argus-node        %s\n' "$(msg '# состояние' '# status')"
  printf '    journalctl --user -u argus-node -f        %s\n' "$(msg '# журнал' '# log')"
  printf '    systemctl --user stop argus-node          %s\n' "$(msg '# остановить' '# stop')"
  printf '    curl -fsSL %s/scripts/install.sh | bash -s -- --uninstall   %s\n' "$RAW" "$(msg '# удалить' '# remove')"
  echo
}

# ------------------------------------------------------------------ uninstall
uninstall() {
  info "Удаляю ноду Argus…" "Removing the Argus node…"
  if [ -f "$DIR/argus-node-linux.sh" ]; then
    ARGUS_NODE_DIR="$DIR" bash "$DIR/argus-node-linux.sh" --uninstall-systemd || true
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now argus-node.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/argus-node.service"
  fi
  rm -rf "$DROPIN_DIR"
  command -v systemctl >/dev/null 2>&1 && { systemctl --user daemon-reload 2>/dev/null || true; }
  pkill -f "$DIR/(src/)?argus-node-linux\.sh" 2>/dev/null || true   # a foreground node, if any
  pkill -f "$DIR/.*rpc-server" 2>/dev/null || true
  if [ -d "$DIR" ]; then
    if ask "Удалить папку $DIR (скрипт, llama.cpp, кэш)?" "Delete $DIR (script, llama.cpp, cache)?" y; then
      rm -rf "$DIR"; ok "Папка удалена." "Folder deleted."
    fi
  fi
  local fw; fw="$(firewall_active)"
  case "$fw" in
    ufw)       msg "Закрыть порт в файрволе:  sudo ufw delete allow ${PORT}/tcp" \
                   "To close the firewall port:  sudo ufw delete allow ${PORT}/tcp" ;;
    firewalld) msg "Закрыть порт в файрволе:  sudo firewall-cmd --permanent --remove-port=${PORT}/tcp && sudo firewall-cmd --reload" \
                   "To close the firewall port:  sudo firewall-cmd --permanent --remove-port=${PORT}/tcp && sudo firewall-cmd --reload" ;;
  esac
  ok "Нода Argus удалена. Не забудьте удалить её в Argus (Cluster)." "Argus node removed. Remember to remove it in Argus (Cluster) too."
}

# ------------------------------------------------------------------ main
main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --foreground|-f) MODE=foreground ;;
      --uninstall)     MODE=uninstall ;;
      --yes|-y)        YES=1 ;;
      --no-firewall)   FIREWALL=0 ;;
      --lang)          shift; UI_LANG="${1:-}" ;;
      --lang=*)        UI_LANG="${1#--lang=}" ;;
      --help|-h)       MODE=help ;;
      *) printf 'unknown option: %s (try --help)\n' "$1" >&2; exit 2 ;;
    esac
    shift
  done
  if [ -z "$UI_LANG" ]; then
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in ru*) UI_LANG=ru ;; *) UI_LANG=en ;; esac
  fi
  [ "$UI_LANG" = "ru" ] || UI_LANG=en
  [ "$MODE" = "help" ] && { usage; exit 0; }

  echo
  msg "${B}Argus — установка ноды для Linux${N}" "${B}Argus — Linux node installer${N}"
  echo
  [ "$(id -u)" -ne 0 ] || warn "Вы запустили установщик от root. Лучше запускать от обычного пользователя (без sudo)." \
                               "You are running as root. It is better to run it as your normal user (no sudo)."

  if [ "$MODE" = "uninstall" ]; then uninstall; exit 0; fi

  check_arch
  detect_distro
  ok "Система: $DISTRO, $ARCH" "System: $DISTRO, $ARCH"
  check_deps
  download_node_script
  maybe_open_firewall

  if [ "$MODE" = "service" ] && ! have_user_systemd; then
    warn "systemd --user недоступен (контейнер, WSL или вход по ssh без сессии) — запускаю ноду в этом окне." \
         "systemd --user is not available (container, WSL or ssh without a session) — running the node in this terminal."
    MODE=foreground
  fi

  if [ "$MODE" = "service" ]; then
    install_service
    banner
    after_service_help
  else
    banner
    msg "Нода работает, пока открыто это окно. Остановить: Ctrl+C." "The node runs while this window is open. Stop: Ctrl+C."
    echo
    ARGUS_NODE_DIR="$DIR" exec bash "$NODE_SH"
  fi
}

main "$@"
