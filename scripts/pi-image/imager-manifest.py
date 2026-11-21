#!/usr/bin/env python3
"""Raspberry Pi Imager manifest helper for the Argus Node image (stdlib only).

  imager-manifest.py base [--name NAME] [--url URL] --out base.json
      Looks the base image up in Raspberry Pi Imager's own OS list (the one Imager downloads on start) and writes
      base.json: url, extract_sha256, init_format, devices, capabilities, icon, release_date + the "imager.devices"
      entries for those devices. Default NAME: "Raspberry Pi OS Lite (64-bit)" (= latest Trixie Lite arm64).
      With --url, the entry whose url matches is used; an unknown url is accepted with empty metadata
      (then the unpacked image cannot be verified and the Imager manifest falls back to Pi 3/4/5 + cloudinit-rpi).
      Also prints key=value lines for $GITHUB_OUTPUT.

  imager-manifest.py manifest --base base.json --image X.img.xz --extract-size N --extract-sha256 S
                              --url URL --out argus-node-pi-arm64.rpi-imager-manifest
      Writes a one-entry Imager manifest ("Argus Node") that downloads URL. Why: Imager 2.x offers NO OS
      customisation (Wi-Fi, user, SSH key) for a local "Use custom" image, because it cannot know the image's
      customisation format. A manifest entry with init_format "cloudinit-rpi" (the same as the official Trixie
      image it is built from) brings the customisation back: double-click the .rpi-imager-manifest file
      (Imager >= 2.0.3) or App Options -> Content Repository -> Use custom file.
      Docs: https://github.com/raspberrypi/rpi-imager/blob/main/doc/os_customisation_formats.md
            https://github.com/raspberrypi/rpi-imager/tree/main/doc/local_json
"""
import argparse
import datetime
import hashlib
import json
import os
import sys
import urllib.request

IMAGER_LIST = "https://downloads.raspberrypi.com/os_list_imagingutility_v4.json"
DEFAULT_NAME = "Raspberry Pi OS Lite (64-bit)"
FALLBACK_DEVICES = ["pi5-64bit", "pi4-64bit", "pi3-64bit"]


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "argus-pi-image"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def walk(entries):
    for e in entries:
        if "subitems" in e:
            yield from walk(e["subitems"])
        elif "url" in e:
            yield e


def cmd_base(a):
    data = fetch_json(IMAGER_LIST)
    entries = list(walk(data.get("os_list", [])))
    if a.url:
        hit = next((e for e in entries if e["url"] == a.url), None)
        if hit is None:
            print(f"::warning::{a.url} is not in the Imager OS list — no checksum/metadata for it", file=sys.stderr)
            hit = {"url": a.url, "name": os.path.basename(a.url)}
    else:
        hit = next((e for e in entries if e.get("name") == a.name), None)
        if hit is None:
            sys.exit(f"'{a.name}' not found in {IMAGER_LIST}")
    tags = set(hit.get("devices") or FALLBACK_DEVICES)
    devices = [d for d in data.get("imager", {}).get("devices", [])
               if not d.get("tags") or tags & set(d["tags"])]
    base = {
        "name": hit.get("name", ""),
        "url": hit["url"],
        "extract_sha256": hit.get("extract_sha256", ""),
        "extract_size": hit.get("extract_size", 0),
        "release_date": hit.get("release_date", ""),
        "init_format": hit.get("init_format", "cloudinit-rpi"),
        "devices": sorted(tags),
        "capabilities": hit.get("capabilities", []),
        "icon": hit.get("icon", ""),
        "imager_devices": devices,
    }
    with open(a.out, "w") as f:
        json.dump(base, f, indent=2)
    for k in ("name", "url", "extract_sha256", "release_date", "init_format"):
        print(f"{k}={base[k]}")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def cmd_manifest(a):
    with open(a.base) as f:
        base = json.load(f)
    init_format = base.get("init_format") or "cloudinit-rpi"
    if init_format not in ("cloudinit-rpi", "cloudinit", "systemd"):
        sys.exit(f"base image init_format '{init_format}' does not allow customisation — refusing to write a manifest")
    entry = {
        "name": "Argus Node (Raspberry Pi OS Lite 64-bit)",
        "description": "Ready Argus Wi-Fi node: starts on boot and appears in Argus → «Найдено в сети». "
                       "Based on " + (base.get("name") or "Raspberry Pi OS Lite (64-bit)")
                       + (" " + base["release_date"] if base.get("release_date") else ""),
        "url": a.url,
        "extract_size": int(a.extract_size),
        "extract_sha256": a.extract_sha256,
        "image_download_size": os.path.getsize(a.image),
        "image_download_sha256": sha256_file(a.image),
        "release_date": datetime.date.today().isoformat(),
        "init_format": init_format,
        "devices": base.get("devices") or FALLBACK_DEVICES,
        "capabilities": base.get("capabilities", []),
    }
    if base.get("icon"):
        entry["icon"] = base["icon"]
    manifest = {"os_list": [entry]}
    if base.get("imager_devices"):
        manifest["imager"] = {"devices": base["imager_devices"]}
    with open(a.out, "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {a.out}: {entry['name']} -> {a.url}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("base")
    b.add_argument("--name", default=DEFAULT_NAME)
    b.add_argument("--url", default="")
    b.add_argument("--out", required=True)
    m = sub.add_parser("manifest")
    m.add_argument("--base", required=True)
    m.add_argument("--image", required=True)
    m.add_argument("--extract-size", required=True)
    m.add_argument("--extract-sha256", required=True)
    m.add_argument("--url", required=True)
    m.add_argument("--out", required=True)
    a = p.parse_args()
    {"base": cmd_base, "manifest": cmd_manifest}[a.cmd](a)


if __name__ == "__main__":
    main()
