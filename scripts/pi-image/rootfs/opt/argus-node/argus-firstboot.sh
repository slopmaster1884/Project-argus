#!/usr/bin/env bash
# Argus Node image: first boot (argus-firstboot.service, root). Gives this node a unique name,
# e.g. "Pi 5 · 3F2A" (model + last 4 hex digits of the MAC), stored in /var/lib/argus-node/node-name.
# Runs again only if that file is deleted. ARGUS_NODE_NAME in /boot/firmware/argus.conf overrides it at runtime.
set -euo pipefail
# shellcheck source=argus-conf.sh
. /opt/argus-node/argus-conf.sh

install -d -m 0750 -o argus -g argus "$ARGUS_STATE"
NAME_FILE="$ARGUS_STATE/node-name"
[ -s "$NAME_FILE" ] && exit 0

# network drivers may still be probing this early: wait up to 20 s for a MAC address
suffix=""
for _ in $(seq 1 20); do
  suffix="$(argus_mac_suffix || true)"
  [ -n "$suffix" ] && break
  sleep 1
done
[ -n "$suffix" ] || suffix="$(tr -dc 'A-F0-9' </dev/urandom | head -c 4 || true)"

name="$(argus_short_model) · ${suffix}"
printf '%s\n' "$name" >"$NAME_FILE.tmp"
chown argus:argus "$NAME_FILE.tmp"; chmod 0644 "$NAME_FILE.tmp"
mv -f "$NAME_FILE.tmp" "$NAME_FILE"
argus_log "имя ноды: $name"
