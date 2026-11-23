# Secured RPC mode (PIN)

[Русский](SECURITY.md)

By default an Argus node runs llama.cpp b12008 `rpc-server` as is: `-H 0.0.0.0 -p 50052`, no password, no
encryption. Any device on the same network can connect and run computations on it (or feed it malformed data —
rpc-server was not designed for untrusted clients).

**Secured mode** is opt-in and off by default. It lets only PCs that paired once with the node's 6-digit PIN
use port 50052.

## Enabling it

**Linux PC / Raspberry Pi**

```bash
ARGUS_SECURE=1 bash scripts/argus-node-linux.sh
# autostart:  ARGUS_SECURE=1 bash scripts/argus-node-linux.sh --systemd
```

The script prints the PIN in the terminal (with systemd: `journalctl --user -u argus-node` or
`cat ~/.local/share/argus-node/pin`). Needs `python3` (standard library only). The node key lives in
`~/.local/share/argus-node/token`; `--reset-token` deletes it so every PC has to pair again.

**Android (Argus Node)** — turn on “Wi-Fi mode”, then the “Защищённый режим” (secured mode) button. The PIN is
shown below it. Over adb: `am start-foreground-service -n com.harkcluster.node/.RpcService --ez wifi true --ez secure true`.

**On the PC (Argus)** — Cluster → “Found on the network”: a secured node has a “🔒 PIN” tag, and “Add” opens a PIN
prompt. When adding by IP, type the PIN into “PIN (if the node is secured)”. A paired node shows “🔒 secured”.
Removing the node in Argus also deletes its key.

You can switch secured mode off at any time and the node becomes a plain one again. A PC that holds the node's key
will **not** silently fall back to an unauthenticated connection: it reports “secured mode is off on the node?
Remove the node and add it again”. A spoofed node therefore cannot quietly strip the protection.

## How it works

```
llama-server --rpc 127.0.0.1:<local port>         (Argus, rpcauth.rs)
   └─ local forwarder ── TCP ──▶ node gateway 0.0.0.0:50052 ──▶ rpc-server 127.0.0.1:50072
                                 (handshake, then raw bytes)
```

* Node: `rpc-server` listens on `127.0.0.1:50072` only; port 50052 belongs to the gateway. The beacon carries `"auth":1`.
* PC: for every secured node Argus keeps a local forwarder on `127.0.0.1:<random port>`. `--rpc` gets the forwarder
  address for secured nodes and the direct address for legacy ones; both can be mixed. Node health checks
  (HELLO/memory) are authenticated too.
* Clients from `127.0.0.1` skip the handshake: that is the adb forward of a phone on a cable (the internal port is
  reachable from the device itself anyway).

### Protocol

ASCII lines ending in `\n`, binary values in hex.

```
node → PC   ARGUS1 <nonce, 16 bytes>              right after accept
login:
PC → node   AUTH <mac>        mac  = HMAC-SHA256(token, "argus-auth|" ‖ nonce)
node → PC   OK <smac>         smac = HMAC-SHA256(token, "argus-srv|" ‖ nonce ‖ mac)  → raw RPC bytes from here
            ERR auth          connection closed
pairing (SPAKE2, RFC 3526 2048-bit group, g = 2):
PC → node   PAIR <X>          X = g^x · M^w
node → PC   PAIRB <Y>         Y = g^y · N^w
PC → node   PAIRC <c>         k = SHA256("argus-spake2|" ‖ nonce ‖ X ‖ Y ‖ Z ‖ w), c = HMAC(k, "c")
node → PC   PAIROK <enc> <s>  enc = token ⊕ HMAC(k, "k"),  s = HMAC(k, "s" ‖ enc)
            ERR pin           wrong PIN
```

`w = HMAC-SHA256("argus-pin", PIN) mod q`, `M = SHA256("argus-spake2-M")² mod p`, `N = SHA256("argus-spake2-N")² mod p`;
group elements are 256-byte big-endian, `w` is 32 bytes. The node token is 32 random bytes. Matching
implementations: `desktop/src-tauri/src/rpcauth.rs` (PC), the python gateway in `scripts/argus-node-linux.sh`,
`android/.../AuthGateway.kt`.

## Threat model, honestly

**Protects against:**

* random or hostile devices on the same network (Wi-Fi neighbours, guests, a compromised smart gadget) that find
  port 50052 and try to use it or attack rpc-server;
* replay: every connection gets a fresh nonce, a recorded `AUTH` answer is useless;
* sniffing the PIN during pairing: the PIN is never sent, and SPAKE2 gives an eavesdropper nothing to test PINs
  against offline. An active attacker gets one guess per pairing attempt; after 5 wrong PINs the node makes a new
  one (≈ 5 in 1,000,000 chance per PIN);
* a fake node posing as a paired one: it does not know the token and cannot answer `OK <smac>`.

**Does NOT protect against:**

* **eavesdropping**: after the handshake RPC traffic is **not encrypted** — model weights, prompts (as activations)
  and outputs are visible to anyone who can watch the network;
* **an active man-in-the-middle** on an established connection: they can wait for a successful login and hijack
  the TCP session. This is not a TLS/VPN replacement. On untrusted networks use WireGuard/Tailscale or USB;
* access to the PC or the node itself: the token is stored in plain text in Argus settings (`argus-settings.json` in the
  config folder) and in a file on the node; whoever can read those files can connect;
* other node ports: the Helper / voice / library roles (50061, 50063, …) are not covered;
* rpc-server vulnerabilities exploited by someone who has the token.

## Limitations

* Older Argus versions don't know about PINs and cannot use a secured node; older (plain) nodes keep working with
  the new Argus exactly as before.
* “Keep model loaded” and secured nodes: the forwarders live inside Argus, so on exit an engine that uses secured
  nodes is stopped (its connections would break anyway).
* USB tethering is not used for a phone in secured mode — Argus stays on the adb forward.
* The key is tied to the node address (`lan:<ip>:<port>`): if the router gives the node another IP, pair again.

## Not verified yet

* The Android part (`AuthGateway.kt`) was run on a JVM against the Rust and Python clients (pairing, login, wrong
  key/PIN rejection, PIN rotation, data piping), but the `RpcService`/`MainActivity` integration and a real phone
  have not been tested.
* No full Tauri build and no live run of a real `llama-server --rpc` through the forwarder (verified: `cargo check`,
  unit tests and an end-to-end forwarder ↔ gateway ↔ echo server test).
