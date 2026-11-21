#!/usr/bin/env bash
# Argus Node image: ExecStartPre=+ of argus-node.service (runs as ROOT before every start).
#  - makes sure the node has a name (first boot did not run / node-name deleted);
#  - /boot/firmware/argus-reset-token (any file) -> forget the secured-mode token, every PC pairs again;
#  - secure mode on: (re)writes /boot/firmware/argus-pin.txt from the kept PIN; off: removes argus-pin.txt.
# Never fails the start: a broken boot partition must not keep the node down.
set -uo pipefail
# shellcheck source=argus-conf.sh
. /opt/argus-node/argus-conf.sh

install -d -m 0750 -o argus -g argus "$ARGUS_STATE" || true
[ -s "$ARGUS_STATE/node-name" ] || /opt/argus-node/argus-firstboot.sh || true

ARGUS_SECURE=0
argus_read_conf || true

if [ -e "$ARGUS_BOOT/argus-reset-token" ]; then
  rm -f "$ARGUS_STATE/token" "$ARGUS_STATE/pin" "$ARGUS_BOOT/argus-reset-token" || true
  argus_log "токен защищённого режима удалён (argus-reset-token) — все ПК должны заново ввести PIN"
fi

if [ "$ARGUS_SECURE" = "1" ]; then
  # the gateway keeps the PIN across restarts (ARGUS_PIN_PERSIST=1); re-export it in case argus-pin.txt was deleted.
  # A brand-new PIN (first start, after argus-reset-token or 5 wrong tries) is exported by argus-pin-export.path.
  if [ -s "$ARGUS_STATE/pin" ]; then /opt/argus-node/argus-pin-export.sh || true; fi
  argus_log "защищённый режим включён (argus.conf): PIN — в $ARGUS_BOOT/argus-pin.txt"
else
  rm -f "$ARGUS_BOOT/argus-pin.txt" || true
fi
sync -f "$ARGUS_BOOT" 2>/dev/null || true
exit 0
