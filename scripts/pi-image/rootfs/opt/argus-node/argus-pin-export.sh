#!/usr/bin/env bash
# Argus Node image: argus-pin-export.service (root), triggered by argus-pin-export.path whenever the secured-mode
# gateway writes a new PIN to /var/lib/argus-node/pin. Copies it to /boot/firmware/argus-pin.txt so a headless user
# can read it by putting the SD card into any PC (the boot partition is the drive called "bootfs").
set -euo pipefail
# shellcheck source=argus-conf.sh
. /opt/argus-node/argus-conf.sh

SRC="$ARGUS_STATE/pin"
DST="$ARGUS_BOOT/argus-pin.txt"
pin="$(tr -dc '0-9' 2>/dev/null <"$SRC" | head -c 6 || true)"
if [ ${#pin} -ne 6 ]; then
  rm -f "$DST"; exit 0
fi
name="$(head -n1 "$ARGUS_STATE/node-name" 2>/dev/null || true)"
{
  printf 'PIN: %s %s\r\n\r\n' "${pin:0:3}" "${pin:3:3}"
  printf 'Argus -> Cluster -> «Найдено в сети» -> «Добавить» -> введите этот PIN.\r\n'
  printf 'Argus -> Cluster -> "Found on network" -> "Add" -> enter this PIN.\r\n\r\n'
  [ -n "$name" ] && printf 'Нода / node: %s\r\n' "$name"
  printf 'PIN не меняется при перезагрузке (новый — после 5 неверных попыток или argus-reset-token).\r\n'
  printf 'После сопряжения он больше не нужен.\r\n'
  printf 'The PIN survives reboots (a new one comes after 5 wrong tries or argus-reset-token).\r\n'
  printf 'Once paired it is not needed again.\r\n'
} >"$DST.tmp"
mv -f "$DST.tmp" "$DST"
sync -f "$ARGUS_BOOT" 2>/dev/null || sync
