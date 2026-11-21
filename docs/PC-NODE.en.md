# A second PC or laptop as an Argus node

[Русская версия](PC-NODE.md)

Got two computers? Let the second one help the first: it lends its memory and CPU (or graphics card), so bigger models fit in Argus. It can be an old laptop, a second PC, a Linux box — anything 64-bit.

- **Main computer** — the one with Argus installed, where you chat.
- **Node (helper)** — the second computer. It does **not** need Argus, only a small node program (llama.cpp `rpc-server`).

> ⚠ **Home only.** The node has no password and no encryption: any device on the same network can connect to it. Don't run it in a cafe, dorm or office, and never forward port 50052 to the internet.

## What you need

1. Both computers on the **same home network**: the same Wi-Fi (not a guest one) or the same router via cable. Cable is faster than Wi-Fi.
2. Internet on the node — once, to download llama.cpp (~25–40 MB; up to 600 MB for NVIDIA cards with CUDA).
3. Argus 0.3 or newer on the main computer.

---

## Option 1. Windows node

### Step 1. Start the node

**Way A — one command.** Press **Win + R**, type `powershell`, press Enter. In the blue window paste (right-click) this and press Enter:

```
irm https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/argus-node-windows.ps1 -OutFile $env:TEMP\argus-node.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\argus-node.ps1
```

**Way B — double-click.** Download the project: on the [GitHub page](https://github.com/slopmaster1884/Project-argus) click the green **Code → Download ZIP**, unzip it, open the `scripts` folder and double-click **`argus-node-windows.cmd`**. If Windows says "Windows protected your PC", click "More info" → "Run anyway".

What the script does:

1. Asks whether to add a **Windows Firewall rule** for port 50052. Answer `y`. Windows shows "Do you want to allow this app to make changes to your device?" — click **"Yes"**. This is the only step that needs administrator rights.
2. Picks the llama.cpp b12008 build by itself: **CUDA** if there's an NVIDIA card with a recent driver; **Vulkan** if there's a graphics driver with Vulkan (AMD, Intel, NVIDIA); otherwise **CPU**. Downloads it to `%LOCALAPPDATA%\ArgusNode`.
3. Starts the node and prints **in big letters the IP address** of this computer and what to click in Argus.

The node runs while the window is open. Stop it with **Ctrl + C**.

If on first start Windows itself asks "Allow `ggml-rpc-server` to communicate on these networks?", tick **"Private networks"** and click "Allow".

The script speaks Russian on a Russian Windows and English otherwise (`-Lang en` forces English).

### Step 2. Autostart (optional)

To start the node by itself when you log in to Windows, run the same thing with `-Install`:

```
powershell -ExecutionPolicy Bypass -File $env:TEMP\argus-node.ps1 -Install
```

or `argus-node-windows.cmd -Install` from the `scripts` folder. The node then runs in the background without a window (task "Argus Node" in Task Scheduler). Log: `%LOCALAPPDATA%\ArgusNode\node.log`.

Remove everything (autostart, firewall rule, files): the same with `-Uninstall`.

Handy options: `-Backend vulkan` (or `cpu`, `cuda`) to choose the build yourself; `-BeaconTarget 192.168.1.10` to send the beacon straight to the main PC (see Troubleshooting); `-Lang en` for English messages.

---

## Option 2. Linux node

Open a terminal (**Ctrl + Alt + T**), paste (**Ctrl + Shift + V**) and press Enter:

```
curl -fsSL https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/install.sh | bash
```

The installer checks everything, asks about the firewall and autostart and shows the IP address. Step by step: [LINUX.en.md, section B](LINUX.en.md#b-linux--helper-node).

---

## Step 3. Add the node on the main computer

1. Open Argus → the **Cluster** tab.
2. In **"Найдено в сети"** (Found on network) find the second computer (by its name) and click **"Добавить"** (Add).
3. In a few seconds the status turns green. Done: next time you start a model, Argus gives the node a share of the layers by itself.

Not in the list? Click **"Добавить ноду по IP"** (Add node by IP) and type the address the script showed, with the port: e.g. `192.168.1.23:50052`.

How to find the second computer's IP yourself:
- **Windows:** Win + R → `cmd` → `ipconfig` → the "IPv4 Address" line under the Wi-Fi or Ethernet adapter.
- **Linux:** `hostname -I` → the first number like `192.168.x.x`.

---

## Troubleshooting

| What you see | Why and what to do |
|---|---|
| The second PC shows up in "Найдено в сети", but after "Добавить" it goes **OFFLINE** | The **firewall** blocks connections to port 50052. Windows: run the script with `-OpenFirewall` and click "Yes". Make sure the network is **Private** in Windows: Settings → Network & internet → Wi-Fi → your network → Network profile type → "Private" (the rule only applies to private networks). Linux: `bash ~/.local/share/argus-node/src/argus-node-linux.sh --open-firewall`. A third-party antivirus with its own firewall (Kaspersky, ESET, Avast…) — allow `ggml-rpc-server.exe` or port 50052 there. |
| The second PC is **not** in "Найдено в сети" | 1) Are both on the same network? A guest Wi-Fi, and on some routers the 5 GHz vs 2.4 GHz networks, are separate networks. 2) Add it by IP (step 3) — that works without the list. 3) **Client isolation** (AP isolation) is on in the router settings — it stops devices from seeing each other; turn it off for your home network. 4) The router drops broadcasts: start the node with the main PC's address — Windows: `-BeaconTarget <main PC IP>`, Linux: `curl … \| ARGUS_BEACON_TARGET=<main PC IP> bash`. |
| Added by IP, still OFFLINE | Test the connection. On the main Windows PC run `Test-NetConnection <node IP> -Port 50052` in PowerShell → you want `TcpTestSucceeded : True`. If `False`: the firewall on the node (see the first row) or client isolation in the router. |
| "Port 50052 is already in use" | The node is already running (e.g. via autostart) — check Task Manager for `ggml-rpc-server.exe`. Or Argus itself is running on this computer: it also uses ports 50052+ for USB phones. Close Argus on the node — the helper doesn't need it. |
| "rpc-server протокол v… — нужен v8" (protocol mismatch) | The node runs a different llama.cpp version. The scripts install exactly b12008; if you installed llama.cpp yourself, remove the node (`-Uninstall` / `--uninstall`) and install it with the script. |
| "rpc-server занят другим клиентом" (busy) | A node serves only one main computer at a time. Close Argus on the other PC or remove this node there. |
| PowerShell refuses to run the script: "running scripts is disabled" | Run it exactly as shown above (`-ExecutionPolicy Bypass`) or via `argus-node-windows.cmd` — no Windows settings need changing. |
| The CUDA download is too big/slow | Use Vulkan: `-Backend vulkan` (~40 MB, works on NVIDIA too). |
| The model got **slower** with the node | Wi-Fi is the bottleneck: every token crosses the network. Connect both PCs to the router with cables, or lower the node's speed weight in its inspector in Argus. If the model fits entirely in the main PC's GPU, Argus leaves the node alone anyway. |

Still stuck? Open an [Issue](https://github.com/slopmaster1884/Project-argus/issues/new) and attach: the node's OS, the last 30 lines of the node window (or `%LOCALAPPDATA%\ArgusNode\node.log`), and on the main PC the **"Копировать журнал"** (Copy log) button.

## ⚠ Security

llama.cpp's `rpc-server` has no passwords and no encryption. The node is **for your home network only**: don't run it on public networks and never open port 50052 to the internet (no port forwarding on the router). The Windows Firewall rule the script adds only applies to **private** networks. To turn the node off: Ctrl+C in its window, or `-Uninstall`.
