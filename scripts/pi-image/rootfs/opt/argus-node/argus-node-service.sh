#!/usr/bin/env bash
# Argus Node image: ExecStart of argus-node.service (runs as the unprivileged `argus` user).
# Reads /boot/firmware/argus.conf, picks the node name and hands over to the regular Linux node script
# (argus-node-linux.sh: static aarch64 rpc-server next to it, UDP beacon on 50053, TCP 50052, ARGUS_SECURE).
set -euo pipefail
# shellcheck source=argus-conf.sh
. /opt/argus-node/argus-conf.sh

export ARGUS_NODE_DIR="$ARGUS_STATE"
argus_read_conf

if [ -z "${ARGUS_NODE_NAME:-}" ]; then
  ARGUS_NODE_NAME="$(head -n1 "$ARGUS_STATE/node-name" 2>/dev/null || true)"
  [ -n "$ARGUS_NODE_NAME" ] || ARGUS_NODE_NAME="$(argus_short_model)"
  export ARGUS_NODE_NAME
fi

exec /opt/argus-node/argus-node-linux.sh
