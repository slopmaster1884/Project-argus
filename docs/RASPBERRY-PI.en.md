# Argus on a Raspberry Pi: the ready-made «Argus Node» image

[Русская версия](RASPBERRY-PI.md) · Linux PC as a node: [LINUX.en.md](LINUX.en.md)

Write the image to a microSD card, put the card into a Raspberry Pi and power it on. A couple of minutes later the Pi shows up in Argus under **"Найдено в сети" (Found on network)**. No terminal, keyboard or monitor needed.

Inside is a regular **Raspberry Pi OS Lite (64-bit)** plus the Argus node, which starts by itself on every boot.

## What you need

| What | Details |
|---|---|
| Raspberry Pi | **5, 4, 400, 500, 3 or Zero 2 W** (64-bit models). More RAM is better: a Pi 5 with 8 or 16 GB lends Argus the most. Pi 1, Pi 2 and the original Zero won't work. |
| microSD card | **8 GB** or more. Everything on it is erased. |
| Power supply | the official one for your model. A weak one makes the Pi slow and reboot. |
| Network | the same home network as the Argus PC: an **Ethernet cable** to the router or **Wi-Fi**. |
| Computer | with a card reader and **Raspberry Pi Imager 2.0.3 or newer** ([download](https://www.raspberrypi.com/software/)). |

## Step 1. Download

Open the [releases page](https://github.com/slopmaster1884/Project-argus/releases). In the latest release:

- `argus-node-pi-arm64.rpi-imager-manifest`: a small file, **take this one** if the Pi will use Wi-Fi;
- `argus-node-pi-arm64.img.xz`: the image itself (~0.6 GB), for a cable connection;
- `argus-node-pi-arm64.img.xz.sha256`: checksum (optional).

## Step 2. Write the card

### Option A: Wi-Fi (or you want SSH)

1. Double-click `argus-node-pi-arm64.rpi-imager-manifest` to open Raspberry Pi Imager.
   If it doesn't open, start Imager and go to **App Options → Content Repository → Edit → Use custom file**, pick the file, then **Apply & Restart**.
2. **Device:** your Raspberry Pi model.
3. **OS:** **Argus Node (Raspberry Pi OS Lite 64-bit)**. Imager downloads and verifies the image itself.
4. **Storage:** your microSD card. Double-check it's the card, not a USB stick!
5. **Customisation:**
   - **Hostname:** keep `argus-node` (or give each Pi its own name if you have several);
   - **Wi-Fi:** network name, password and **country**. Without the country Wi-Fi may stay off;
   - **User and password:** only if you want to log in over SSH. The node doesn't need one;
   - **SSH:** turn on if you set a user.
6. **Write** and wait until Imager has written and verified the card.

### Option B: Ethernet cable (no settings at all)

1. In Raspberry Pi Imager: **Device** → your model, **OS** → scroll down → **Use custom** → pick `argus-node-pi-arm64.img.xz`.
2. **Storage:** your microSD card → **Write**.

Imager won't offer customisation (Wi-Fi, user) here, because Imager 2.x disables it for local image files. A cable doesn't need it. Need Wi-Fi? Use option A or see [Wi-Fi without Imager](#wi-fi-without-imager).

## Step 3. Power on

1. Put the card into the Raspberry Pi. For option B, plug in the network cable.
2. Connect power.
3. Wait **~2 minutes**. On first boot the Pi expands the system to the whole card and may reboot once by itself. That's normal.

## Step 4. Add the node in Argus

On the main PC: **Argus → Cluster → "Найдено в сети" (Found on network)**. A node named like **"Pi 5 · 3F2A"** appears (the model plus the last 4 characters of its network address, unique per Pi). Click **"Добавить" (Add)**. The status turns green.

That's it. On every power-on the node starts by itself.

## Secured mode (PIN), no monitor or keyboard needed

Without secured mode any device on your network can connect to the node. With it, only PCs that entered the PIN can (needs Argus 0.3.5+; details and the honest threat model are in [SECURITY.en.md](SECURITY.en.md)).

1. Put the card into your PC. A drive called **bootfs** appears.
2. Open `argus.conf` on it in a text editor, remove the `#` in front of `#ARGUS_SECURE=1` and save.
3. Put the card back, power the Pi on and wait ~2 minutes. The node creates a PIN and writes it to the card.
4. Power the Pi off (just unplug it), put the card into your PC and open **`argus-pin.txt`** on the **bootfs** drive: it holds the 6-digit PIN.
5. Card back, Pi on. In Argus: "Found on network" → "Add" → enter the PIN.

The PIN **survives reboots**. A new one is only generated after 5 wrong attempts or after you reset pairing (below); then check `argus-pin.txt` again. Once paired, the PIN isn't needed any more: the PC remembers the node key. Over SSH: `cat /boot/firmware/argus-pin.txt`.

To unpair every PC, create an empty file named `argus-reset-token` (no extension) on the **bootfs** drive. On the next start the node forgets its key and deletes the file.

## Settings: `argus.conf`

It's on the **bootfs** drive (`/boot/firmware/argus.conf` on the Pi). Lines starting with `#` are off. After a change, reboot the Pi (or run `sudo systemctl restart argus-node`).

| Line | What it does |
|---|---|
| `ARGUS_SECURE=1` | secured mode, PIN in `argus-pin.txt` |
| `ARGUS_NODE_NAME=Kitchen Pi` | your own name in Argus instead of "Pi 5 · 3F2A" |
| `ARGUS_THREADS=3` | how many CPU cores to use (default: all) |
| `ARGUS_PORT=50052` | TCP port (no need to change) |
| `ARGUS_BEACON_TARGET=192.168.1.10` | the main PC's IP, if the node never shows up in "Found on network" (router blocks broadcast) |

## Wi-Fi without Imager

Wrote the image with "Use custom" (option B) and have no cable? Put the card into your PC, open `network-config` on the **bootfs** drive and append (indent with spaces, not tabs):

```yaml
network:
  version: 2
  wifis:
    renderer: NetworkManager
    wlan0:
      dhcp4: true
      regulatory-domain: "GB"
      access-points:
        "Your-network-name":
          password: "your-wifi-password"
      optional: true
```

Use your own two-letter country code. This only works **before the first boot** (cloud-init applies it once). If the Pi has already booted, re-writing the card is easiest.

## SSH (optional)

SSH is on, but **there is no default password**: you can only log in if you set a user in Imager (option A). Then:

```
ssh your-user@argus-node.local
```

(`argus-node.local` not found? Use the Pi's IP from your router.)

| What | Command |
|---|---|
| Is the node running? | `systemctl status argus-node` |
| Log | `journalctl -u argus-node -f` (Ctrl+C to quit) |
| Restart | `sudo systemctl restart argus-node` |
| Node name | `cat /var/lib/argus-node/node-name` |
| Build info | `cat /opt/argus-node/BUILD-INFO` |

## What's in the image

- Raspberry Pi OS Lite (64-bit), Debian Trixie, exactly as from raspberrypi.com: its first-boot setup (cloud-init, Imager customisation) works as usual.
- `/opt/argus-node`: the same node script as for Linux ([LINUX.en.md](LINUX.en.md)) and the static arm64 rpc-server builds also used by Argus Node on Android. The node needs no internet and downloads nothing.
- The `argus-node` service starts at boot and runs as its own unprivileged user `argus`. If it crashes, it restarts.
- Hostname `argus-node`. The node's Argus name is set on first boot: "Pi 5 · 3F2A".
- SSH is enabled the standard Raspberry Pi way (an `ssh` file on bootfs), with no default password.
- Swap: zram, the Raspberry Pi OS Trixie default (rpi-swap package), unchanged.
- No firewall (Raspberry Pi OS ships none), so ports 50052 (TCP) and 50053 (UDP) need no opening. If you install `ufw` yourself, open the port: `sudo ufw allow 50052/tcp`.

## Several Raspberry Pis

Each node names itself from its network address, so they don't get mixed up in Argus. The hostname is `argus-node` on all of them; if you use SSH, give each its own in Imager (`argus-node-1`, `argus-node-2`…).

## Updating

New image out? Just write the card again. Copy your `argus.conf` off the **bootfs** drive first if you changed it. The Pi keeps the same node name (it comes from the network address), but in secured mode the PCs have to pair again.

## Troubleshooting

| What you see | What to do |
|---|---|
| No node in "Found on network" after 3–4 minutes | Pi and PC must be on the same (non-guest) network. Check the Pi appears in your router's device list. Wi-Fi: check the network name, password and country in Imager. Try 2.4 GHz instead of 5 GHz. |
| Pi shows in the router but not in Argus | The router may block broadcast ("client isolation", AP isolation). In Argus use **"Добавить ноду по IP" (Add node by IP)** with `Pi-IP:50052`, or set the PC's IP in `ARGUS_BEACON_TARGET` in `argus.conf`. |
| Node appears, but goes OFFLINE after "Add" | Secured mode on? Enter the PIN from `argus-pin.txt`. Argus older than 0.3.5 can't use secured nodes: update Argus or turn secured mode off. |
| Red LED blinking, Pi reboots | Weak power supply or cable. Use the official one. |
| Imager offers no customisation | You picked the file via "Use custom". For Wi-Fi open the `.rpi-imager-manifest` file (option A). Also update Imager to 2.0.3+: Imager 1.x silently fails to apply settings to this image. |
| "rpc-server протокол v… — нужен v8" | Image and Argus versions differ. Use the image from the same release as your Argus. |

Still stuck? Open an [issue](https://github.com/slopmaster1884/Project-argus/issues/new) with your Pi model, Argus version and (if you have SSH) the output of `journalctl -u argus-node -n 50 --no-pager`.

## ⚠ Security

Without secured mode the node listens on port 50052 with no password. Use it **at home only** and never forward ports 50052/50053 to the internet. PIN mode keeps other devices on your network out, but doesn't encrypt traffic ([SECURITY.en.md](SECURITY.en.md)).

## Build the image yourself

GitHub Actions builds it: **Actions → pi-image → Run workflow**. After ~20 minutes the image is in the run's artifacts. The build takes the official Raspberry Pi OS Lite image, verifies its checksum and customises it on an arm64 machine (`scripts/pi-image/build-image.sh`). By hand, on arm64 Linux as root:

```
sudo scripts/pi-image/build-image.sh 2026-10-06-raspios-trixie-arm64-lite.img.xz out/argus-node-pi-arm64.img
```
