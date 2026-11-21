# shellcheck shell=bash
# Argus Node image: shared helpers, sourced by the other /opt/argus-node/*.sh scripts.
#
# /boot/firmware/argus.conf is a plain KEY=VALUE text file on the FAT boot partition, so a headless user can
# edit it on any PC (Windows Notepad included: CRLF line endings and a UTF-8 BOM are accepted).
# It is PARSED, never sourced: only the keys below are taken, everything else is ignored with a warning.
#   ARGUS_SECURE=1            PIN + token auth gateway (docs/SECURITY.md); PIN goes to /boot/firmware/argus-pin.txt
#   ARGUS_NODE_NAME=Pi кухня  name shown in Argus (default: "Pi 5 · 3F2A" = model + last 4 hex of the MAC)
#   ARGUS_THREADS=4           rpc-server threads (default: all cores)
#   ARGUS_PORT=50052          TCP port (default 50052)
#   ARGUS_BEACON_TARGET=192.168.1.10   also send the beacon to this PC (router filters broadcast)

# shellcheck disable=SC2034 # ARGUS_STATE / ARGUS_BOOT are used by the scripts that source this file
ARGUS_CONF="${ARGUS_CONF:-/boot/firmware/argus.conf}"
ARGUS_STATE="${ARGUS_NODE_DIR:-/var/lib/argus-node}"
ARGUS_BOOT="${ARGUS_BOOT:-/boot/firmware}"

argus_log() { printf '[argus-image] %s\n' "$*" >&2; }

_argus_trim() { # var-name: strip leading/trailing blanks in place
  local v="${!1}"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  printf -v "$1" '%s' "$v"
}

# argus_read_conf: export the recognised keys from $ARGUS_CONF (missing file = all defaults)
argus_read_conf() {
  local line key val n=0
  [ -r "$ARGUS_CONF" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    [ "$n" = 1 ] && line="${line#$'\357\273\277'}"    # UTF-8 BOM (Notepad)
    _argus_trim line
    case "$line" in ''|'#'*|';'*) continue ;; esac
    case "$line" in *=*) ;; *) argus_log "argus.conf:$n: нет '=' — строка пропущена"; continue ;; esac
    key="${line%%=*}"; val="${line#*=}"
    _argus_trim key; _argus_trim val
    key="${key#export }"; _argus_trim key
    case "$val" in \"*\") val="${val#\"}"; val="${val%\"}" ;; \'*\') val="${val#\'}"; val="${val%\'}" ;; esac
    case "$key" in
      ARGUS_SECURE)
        case "$val" in 1|yes|true|on|YES|TRUE|ON|Yes|True|On|да|Да|ДА) val=1 ;; *) val=0 ;; esac ;;
      ARGUS_THREADS|ARGUS_PORT|ARGUS_INTERNAL_PORT)
        case "$val" in ''|*[!0-9]*) argus_log "argus.conf:$n: $key=$val — нужно число, игнорирую"; continue ;; esac ;;
      ARGUS_NODE_NAME|ARGUS_BEACON_TARGET)
        [ -n "$val" ] || continue ;;
      *) argus_log "argus.conf:$n: неизвестный параметр «$key» — пропущен"; continue ;;
    esac
    printf -v "$key" '%s' "$val"
    export "${key?}"
  done <"$ARGUS_CONF"
}

# argus_default_name: "Pi 5 · 3F2A" (short model + last 4 hex digits of the wired, else wireless, MAC)
argus_short_model() {
  local m=""
  [ -r /proc/device-tree/model ] && m="$(tr -d '\0' </proc/device-tree/model)"
  [ -n "$m" ] || { hostname; return; }
  m="${m#Raspberry }"          # "Pi 5 Model B Rev 1.0"
  m="${m%% Rev *}"             # "Pi 5 Model B"
  m="${m%% Model *}"           # "Pi 5"
  case "$m" in "Pi Compute Module "*) m="CM${m#Pi Compute Module }" ;; esac
  printf '%s' "$m"
}

argus_mac_suffix() {
  local i f mac
  for i in eth0 end0 wlan0; do
    f="/sys/class/net/$i/address"
    [ -r "$f" ] && mac="$(cat "$f")" && [ -n "$mac" ] && [ "$mac" != "00:00:00:00:00:00" ] && break
    mac=""
  done
  if [ -z "$mac" ]; then
    for f in /sys/class/net/*/address; do
      case "$f" in */lo/*) continue ;; esac
      mac="$(cat "$f" 2>/dev/null || true)"
      [ -n "$mac" ] && [ "$mac" != "00:00:00:00:00:00" ] && break
      mac=""
    done
  fi
  mac="${mac//:/}"
  [ ${#mac} -ge 4 ] || return 1
  mac="${mac: -4}"
  printf '%s' "${mac^^}"
}
