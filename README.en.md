<div align="center">

# ARGUS

**Run a local LLM on your GPU plus the old phones in your drawer.**

![version](https://img.shields.io/badge/version-0.3.4-00e5ff)
![platform](https://img.shields.io/badge/Windows_·_Linux_·_Android-7c4dff)
![engine](https://img.shields.io/badge/engine-llama.cpp-ff4081)
![license](https://img.shields.io/badge/free-open_source-00e676)

[Download](../../releases) · [Quick start](#quick-start) · [Linux](#linux) · [Second PC](#second-pc--laptop-as-a-node) · [Support](SUPPORT.md) · [Русский](README.md)

**Built by one person on a GTX 960. If it's useful to you, [chip in for test hardware](SUPPORT.md) ❤️**

![Argus](docs/screens/04-cluster-lan.png)

</div>

## What it is

A decent LLM wants 16–24 GB of VRAM. I have a GTX 960 with 4 GB. But I also have a few old Android phones with 6–12 GB of RAM each.

Argus joins your PC and your phones into one llama.cpp cluster. Phones connect over USB or Wi-Fi, the model's layers are split across the GPU, the PC's CPU and the phones, and you just chat. Everything runs at home: no cloud, no subscription.

No root needed. The phone gets a regular app, Argus Node, which runs llama.cpp's `rpc-server`.

## How it works

Argus benchmarks each device on connect (speed and free memory) and hands out layers so tokens come out as fast as possible. If the model fits in VRAM alone, phones aren't used at all, because that's fastest.

- PC side: Tauri 2 app (Rust + React/TS) running `llama-server` (llama.cpp b12008, Vulkan or CUDA) with `--rpc` pointing at the nodes.
- Phone side: native APK with a static musl `rpc-server`. USB goes through `adb forward` or, since 0.3.4, through USB tethering. On my setup (GTX 960 + phones, Gemma 2 2B) tethering took generation from 16 to 36 tokens/s compared to `adb forward`. Wi-Fi nodes announce themselves via UDP beacon on port 50053.
- Linux PCs, Raspberry Pi and a second Windows PC can be nodes too: see [Linux](#linux) and [Second PC / laptop as a node](#second-pc--laptop-as-a-node).

## Features

- Plug a phone in, allow USB debugging, and Argus installs the node app and starts it.
- Hugging Face search inside the app, with a "will it fit" check and one-click download.
- Chat with multiple conversations, code blocks, files and live tokens/s.
- OpenAI-compatible API: works with Open WebUI, Jan, Continue, Hermes.
- Speculative decoding: a small draft model on the GPU, the big one verifies.
- MoE models like Qwen3 30B-A3B: experts live on the phones, only a small part of the model works per token.
- Thermal-aware split: a hot phone gets less work.
- Phones as helpers: a small model for titles and summaries, voice input (whisper.cpp), offline Wikipedia (Kiwix .zim) as a tool for the model.
- Chat from any phone on your home network via QR code (PIN-protected), image input, RAG over your folders, overnight queue, Telegram bot.
- Never updates itself silently: every update (PC or phone) asks first and is checked against SHA-256.

## Quick start

1. Get **Argus-Setup.exe** (Windows) or AppImage / .deb (Linux) from [releases](../../releases).
2. On the phone: Settings → About phone → tap "Build number" 7 times → Developer options → **USB debugging**.
3. Plug in the cable and accept the debugging prompt.
4. In Argus press **"Pick a model and start"**.
5. When the status says "Ready", chat.

The installer isn't signed yet, so SmartScreen may complain: "More info" → "Run anyway".

Without a cable: turn on "Wi-Fi режим" in Argus Node and the phone appears under Cluster → "Найдено в сети" (Found on network).

## Linux

Argus runs on Linux too (AppImage / .deb): you need a Vulkan driver, and udev rules for USB phones (`sudo apt install android-sdk-platform-tools-common`).

To turn a Linux PC, laptop or Raspberry Pi into a **helper node**, run one command in a terminal:

```
curl -fsSL https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/install.sh | bash
```

The installer checks everything, asks about the firewall and autostart, and tells you what to click in Argus. Step by step for beginners: [docs/LINUX.en.md](docs/LINUX.en.md).

## Second PC / laptop as a node

A second computer (Windows or Linux) can lend Argus its memory and GPU over your home network. It doesn't need Argus installed.

- **Windows:** Win + R → `powershell` → paste and press Enter:
  ```
  irm https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/argus-node-windows.ps1 -OutFile $env:TEMP\argus-node.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\argus-node.ps1
  ```
  Or download the project and double-click `scripts\argus-node-windows.cmd`.
- **Linux:** the command from the section above.

Then on the main PC: **Cluster → "Найдено в сети" → "Добавить"** (or "Добавить ноду по IP" / Add node by IP). Details and what to do if it doesn't show up: [docs/PC-NODE.en.md](docs/PC-NODE.en.md).

⚠ The node has no password: home network only, never expose port 50052 to the internet.

## What fits

| Total memory | Model | Good for |
|---|---|---|
| 4–6 GB | Qwen3 4B | Q&A, translation |
| 8–10 GB | Qwen3 8B, Hermes 3 8B | Code, agent |
| 10–12 GB | Qwen2.5-VL 7B | Images |
| 18 GB+ | Qwen3 30B-A3B (MoE) | Smartest, still fast |

## Security, honestly

llama.cpp's `rpc-server` has no authentication. In Wi-Fi mode and in USB tethering mode the phone listens on port 50052 on all interfaces, so anything on the same Wi-Fi can connect to it. In plain USB mode (adb forward) only the PC can reach it.

So: use Wi-Fi and tethering modes only on your own home network, and never expose ports 50052, 50053, 50061, 50063 or 50080 to the internet. Optional secured mode (“Защищённый режим” in Argus Node, `ARGUS_SECURE=1` for the Linux node) lets only PCs paired with the node’s PIN connect. It adds no encryption — see [docs/SECURITY.en.md](docs/SECURITY.en.md) for the threat model.

## Is it fast?

One big GPU is faster. The point is running models that didn't fit at all before. Phones get warm: take them out of the case and cap charging at 85% if your phone supports it.

## For developers

Architecture and build: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Node roles and protocol: [docs/ROLES.md](docs/ROLES.md) (Russian for now).

Note for anyone shipping static musl servers on Android: patch `accept` → `accept4(..., SOCK_CLOEXEC)`, otherwise seccomp kills the process with SIGSYS on arm64.

## Support

Argus is free and will stay free. If it helped you, [support it here](SUPPORT.md). Everything goes to test hardware.
