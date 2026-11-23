#!/usr/bin/env bash
# Gives release assets human-readable labels (GitHub shows the label instead of the file name).
# File names stay the same: the updater and README links depend on them.
# Usage: GH_TOKEN=... bash scripts/label-release-assets.sh <tag> [owner/repo]
set -euo pipefail
TAG="$1"; REPO="${2:-$GITHUB_REPOSITORY}"
label_for() {
  case "$1" in
    Argus-Setup.exe) echo "1. Windows — Argus (установщик, качать это)";;
    *.AppImage) echo "2. Linux — Argus, AppImage (любой дистрибутив)";;
    *.deb) echo "2. Linux — Argus, .deb (Ubuntu, Debian, Mint)";;
    Argus-Node.apk) echo "3. Android — Argus Node (на телефоны-помощники)";;
    *.img.xz) echo "4. Raspberry Pi — образ ноды (через Raspberry Pi Imager)";;
    install.sh) echo "Служебное: установка Linux-ноды (её запускает команда из инструкции)";;
    argus-node-linux.sh) echo "Служебное: скрипт Linux-ноды";;
    SHA256SUMS.txt) echo "Служебное: контрольные суммы";;
    *.img.xz.sha256) echo "Служебное: контрольная сумма образа Pi";;
    *.rpi-imager-manifest) echo "Служебное: манифест для Raspberry Pi Imager";;
    *) echo "";;
  esac
}
gh api "repos/$REPO/releases/tags/$TAG" --jq '.assets[] | "\(.id) \(.name)"' | while read -r id name; do
  l=$(label_for "$name"); [ -n "$l" ] || continue
  gh api -X PATCH "repos/$REPO/releases/assets/$id" -f name="$name" -f label="$l" >/dev/null && echo "labeled $name"
done
