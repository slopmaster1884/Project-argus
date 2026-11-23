# Node roles (plan of 2026-11-01, status as of 0.4)

Русская версия: [ROLES.md](ROLES.md)

> **Status 0.4:** **Helper** is a normal feature (the “Roles” switch in Cluster is on by default; a 0.3.x user who had
> assigned a Helper and then turned the experiment off keeps it off). A node gets the model only when it has enough free
> memory. **Task routing** (task type → role → node, fallback to the PC) is used by the Queue, agent subtasks and file
> search. **Search** is a node role (llama-server `--embedding` on :50060, Argus Node 0.4) with PC embeddings as fallback.
>
> **Status 0.3.3 (node):** unified role protocol (below), Voice (whisper-server) and Library (kiwix-serve) in the APK, temperature/battery telemetry.
>
> **Status 0.3.2:** warm-up, node speed test, speed-aware layer split, roles “Auto / Model part / Free” and the experimental **Helper** role.

Without roles all nodes work as one model (layer pipeline): every token passes GPU → node 1 → node 2 in turn. Extra nodes add memory, not speed.

With “Roles” every device does its own job at the same time, and Argus on the PC hands out the work.

## Roles
| Role | What it does | Engine on the node | Port (adb forward) |
|---|---|---|---|
| Model part | layers of the main model | rpc-server | 50052 (PC 50052+) — ✅ |
| Helper | small 0.6–4B model: summaries, chat titles, translation, Queue chunks, agent subtasks | llama-server (arm64) | 50062 (PC 50162+) — ✅ 0.4, on by default |
| Search | embeddings for file search (RAG, “Knowledge” tab) | llama-server --embedding | 50060 (PC 50160+) — ✅ 0.4 (Argus Node 0.4) |
| Voice | speech recognition | whisper.cpp server | 50061 — ✅ 0.3.3 |
| Library | offline Wikipedia | kiwix-serve | 50063 — ✅ 0.3.3 |
| Free | nothing, stays cool | — | — — ✅ 0.3.2 |

## How it works
1. Each node is benchmarked when it connects: speed (GB/s, tok/s estimate), RAM, temperature.
2. Auto layout: the main model takes the GPU + the fewest fastest nodes it needs to fit; the rest are “Free”. Helper / Search / Voice / Library are assigned by the user (no automatic assignment by RAM/speed yet); a node gets a role model only with enough free RAM.
3. Role models are downloaded to the PC once and sent to the node (HTTP :50055 — over the cable through `adb reverse`, or over Wi‑Fi), kept in the node app's private storage.
4. The node app gets “role X, model Y” and starts the engine next to rpc-server.
5. Task queue on the PC: task type → role → node; if the node disappears, the task goes to the PC CPU or the main model (✅ 0.4, see “Task routing”).
6. Who did what is shown in the Queue job card and in the agent's subtask result.

## Example (author's hardware)
- GTX 960 + a fast phone: Qwen3 4B — chat ~14 tok/s.
- Note10+ (12 GB): Search + Helper (Qwen3 1.7B).
- A52: Voice (whisper small).

## Limits
- A single answer does not get faster; the whole system gets faster and richer.
- Phone heat/battery, RAM of each node.

## Milestones
- ✅ 0.3.2: warm-up, node speed test, speed-aware split with a “≈N tok/s” estimate, spare nodes → “Free”, manual roles Auto / Model part / Free.
- ✅ 0.3.2 (experiment “Roles”, off by default): llama-server on the node (libllama_server.so in the APK), role assignment, model transfer from the PC, **Helper** (Qwen3 0.6B / 1.7B / 4B or your own GGUF): chat titles, “Summary”, “Parallel test”.
- ✅ 0.3.3: Voice + Library, unified role protocol, telemetry.
- ✅ 0.4: Helper out of the experiment (+ free-RAM check), task queue (task type → role → node, PC fallback), agent subtasks (`subtask` tool).
- ✅ 0.4: file search — the Search role on a node (Argus Node 0.4, versionCode 8) with PC embeddings as fallback.
  Not yet: automatic role assignment by RAM/speed (the user picks roles); “who did what” inside the chat feed.

## Task routing (0.4)

The rules are pure functions in `desktop/src-tauri/src/route.rs` (unit-tested); `queue.rs`, `helper.rs`, `rag.rs` use them.

| Task type | Role | Node | Fallback |
|---|---|---|---|
| summary / chat title, translation, agent subtask | Helper | the ready Helper with the fewest requests in flight (USB before Wi‑Fi) | main model on the PC |
| “Custom prompt” Queue job | — | — | main model only |
| embeddings (“Knowledge”, `search_files`) | Search | a node with Search (custom URL → nodes → PC) | llama-server with the same model on the PC (:50070) |
| speech recognition | Voice | phone with whisper | (as in 0.3.3) |

- **Silent fallback:** if a node does not answer or disappears in the middle of a job, that piece is redone on the next
  node or on the main model; the node is skipped for the rest of the file/subtask. With neither a node nor a running
  model, the Queue waits.
- **Queue:** a job has route `auto` (default for translate/summarize: a Helper when one is free) or `main` (main model
  only — custom prompts and jobs saved by 0.3.x). Helper chunks are half size (its context is 4096). The job card shows
  who did the work (“main model”, “Helper «Note10+»”).
- **Agent subtasks:** the `subtask` tool (`summarize | translate | extract`, text up to 60,000 characters) → Rust
  `subtask_run`; long text is split, each piece goes to a Helper or the main model. It only reads text, so it is not a
  “dangerous” tool (confirmation works like for the other tools).
- **Memory safety:** a Helper needs free RAM ≈ model × 1.5 + 512 MB, Search ≈ model + 384 MB
  (`route::helper_need_mb`, `search_need_mb`). A node with less does not get the model (one already running keeps it);
  the UI says “Not enough free memory…” and tasks go to the PC. A node that reports no RAM figure (0) is not blocked.
- **Search and the index:** the node gets the same file the PC runs itself (`nomic-embed-text-v1.5.Q8_0.gguf`), so an
  index built on a node works on the PC and vice versa. If the fallback service runs another model, search asks to
  re-index (as before).

## Node role protocol (Android, since 0.3.3, versionCode 7; Search since 0.4, versionCode 8)

rpc-server (“Model part”) always runs; other roles start **next to** it and don't exclude each other.
rpc-server takes the big cores (`-t` = big+prime, `force_threads` overrides); Helper, Voice and Search default to the
little cores (`-t` = number of little cores, at least 2); when `toybox taskset` works the role process is pinned to the
little cores (best effort; not pinned when there are more threads than little cores).

### USB commands (adb)
`adb shell am start-foreground-service -n com.harkcluster.node/.RpcService <extras>`

| Extra | Meaning |
|---|---|
| `--es role rpc\|helper\|voice\|library\|search\|idle` | start role(s) (comma separated). `rpc` does nothing (rpc-server always runs), `idle` stops all roles but rpc |
| `--es role_stop helper\|voice\|library\|search\|all` | stop role(s) and **forget** the assignment (handled before `role`) |
| `--es helper_model <file.gguf> --es helper_url <url> [--el helper_size N] [--ei helper_threads N]` | Helper (llama-server). Works without `role` too (as in 0.3.2) |
| `--ez helper_stop true` | legacy = `role_stop helper` |
| `--es voice_model <file.bin> --es voice_url <url> [--el voice_size N] [--ei voice_threads N]` | Voice (whisper-server); `voice_url` usually `http://127.0.0.1:50055/helper/<file>` (adb reverse) |
| `--es search_model <file.gguf> --es search_url <url> [--el search_size N] [--ei search_threads N]` | Search (llama-server `--embedding --pooling mean -c 2048`, 0.4). `role` = `search` (or `embeddings`) |
| `--es zim <file.zim>` | Library: file name in `filesDir/zim` (or an absolute path). Without `zim` — the last assigned, else the newest .zim |
| `--ez wifi true\|false`, `--ei port`, `--ei force_threads` | as before |
| action `com.harkcluster.node.STOP` | stop the node; role assignments are **kept** and come back on the next start |

Assignments are kept in SharedPreferences `node` (`role_helper`, `role_voice`, `role_library`, `role_search`) and are
relaunched when the service restarts (START_STICKY, APK update, “Start node”). Any role stop (`role_stop`, `role=idle`,
`helper_stop`, `"<role>": false` in the beacon reply) works whatever source assigned the role.

### Ports
| Role | Engine | Port on the phone | Address (USB / Wi‑Fi) |
|---|---|---|---|
| rpc | librpc_server*.so | 50052 | 127.0.0.1 / 0.0.0.0 |
| helper | libllama_server.so | 50062 | 127.0.0.1 / 0.0.0.0 |
| voice | libwhisper_server.so (whisper.cpp v1.9.5, armv8.2+dotprod) | 50061 | 127.0.0.1 / 0.0.0.0; API `POST /inference` (multipart `file` = 16 kHz WAV) |
| library | libkiwix_serve.so (kiwix-tools 3.8.2) | 50063 | `-i 127.0.0.1` / `-i ipv4`; `-a <app pid>` |
| search (0.4) | libllama_server.so `--embedding` | 50060 | 127.0.0.1 / 0.0.0.0; API `POST /v1/embeddings`, ready = `GET /health` → 200 |

### Status over USB (dumpsys)
`adb shell dumpsys activity service com.harkcluster.node/.RpcService` prints:
- `argus-helper state=… pct=… model=… error=…` (as in 0.3.2)
- `argus-status {json}` — **one JSON line** (since 0.3.3)
- `argus-rpc …`, `argus-bench …` (as before)

```json
{"argus":"status","v":1,"vn":"0.4.0","vc":8,
 "temp_c":38.5,"battery_temp_c":34.0,"cpu_temp_c":38.5,"thermal_status":0,"throttled":false,
 "battery_pct":81,"charging":true,"usb_net_ip":"192.168.42.129","wifi_ip":"192.168.1.23",
 "rpc":{"state":"linked","port":50052,"threads":4,"big_cores":4,"variant":"dotprod","mode":"usb"},
 "roles":{"helper":{"state":"ready","pct":100,"port":50062,"threads":4,"model":"Qwen3-1.7B-Q4_0.gguf"},
          "voice":{"state":"idle","port":50061,"pct":0,"threads":0},
          "library":{"state":"ready","port":50063,"zim":"wikipedia_en_all_mini.zim"},
          "embeddings":{"state":"ready","port":50060,"pct":100,"threads":4,"model":"nomic-embed-text-v1.5.Q8_0.gguf"}}}
```
Role states: `idle | downloading | starting | ready | error` (+ `error`, `pct`; library also `import_pct` while a .zim is copied).
The `embeddings` key exists only on Argus Node 0.4+: that is how the PC knows Search can be offered (older nodes don't
see it). Helper and Search share one binary; on start each kills leftover processes of its own kind only (told apart by
the `--embedding` argument).

Optional fields (`temp_c`, `cpu_temp_c`, `battery_pct`, `usb_net_ip`, `wifi_ip`) are absent when unknown.

- `temp_c` = max(battery temperature `EXTRA_TEMPERATURE/10`, max of `/sys/class/thermal/thermal_zone*/temp`; zones are often SELinux-denied → battery only).
- `throttled` = `PowerManager.currentThermalStatus ≥ THERMAL_STATUS_MODERATE` (Android 10+, else false); `thermal_status` is the raw 0…6 value.
- `usb_net_ip` — IPv4 of an `rndis*`/`ncm*`/`usb*` interface (USB tethering).

### Status over Wi‑Fi (UDP beacon :50053)
The beacon JSON carries the same telemetry fields and `"roles": {helper, voice, library}` (+ `embeddings` since 0.4).
The old `"helper"` field stays. The PC ignores unknown keys.

The PC's beacon reply (`{"argus":"host",…}`) may contain `"helper": {file,path,size,threads} | false`,
`"voice": {file,path,size,threads} | false`, `"library": {"zim":…} | false`, `"search": {file,path,size} | false` (0.4);
a missing key means no change. Older nodes ignore the unknown `search` key.

### Library on the phone
“Choose .zim” (system file picker, SAF) copies the file into `filesDir/zim` with progress. If Library is running it
switches to the new file. The PC turns the role on with `--es role library [--es zim <name>]`.

### Heat hint
When the phone is charging and `temp_c ≥ 40` or `throttled`, the app shows: “If it's charging and getting hot — limit
charging to 85% in the battery settings”.
