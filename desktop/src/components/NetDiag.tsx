import { useEffect, useRef, useState } from "react";
import { Check, ChevronDown, ChevronRight, Copy, Loader2, Minus, Stethoscope, X } from "lucide-react";
import clsx from "clsx";
import { diagnoseNode } from "../lib/api";
import { t as tr, useLang, type I18nKey } from "../lib/i18n";
import { useCluster } from "../store/cluster";
import type { DiagHint, DiagReport, DiagStep, DiagStepId } from "../lib/types";
import ErrorBox from "./ErrorBox";

const STEPS: DiagStepId[] = ["subnet", "beacon", "tcp", "hello"];
const DEFAULT_PORT = 50052;

/** "192.168.1.5", "192.168.1.5:50052", "[fe80::1]:50052", "lan:192.168.1.5:50052" → { ip, port } */
export function parseNodeAddress(raw: string): { ip: string; port: number } | null {
  let s = raw.trim().replace(/^lan:/, "");
  if (!s) return null;
  let port = DEFAULT_PORT;
  const v6 = s.match(/^\[([^\]]+)\](?::(\d+))?$/);
  if (v6) { s = v6[1]; if (v6[2]) port = Number(v6[2]); }
  else {
    const m = s.match(/^([^:]+):(\d+)$/);
    if (m) { s = m[1]; port = Number(m[2]); }
  }
  if (!(port > 0 && port < 65536)) return null;
  const ok4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.test(s) && s.split(".").every((o) => Number(o) <= 255);
  if (!ok4 && !(v6 && s.includes(":"))) return null;
  return { ip: s, port };
}

/** commands shown under a hint (with the real port) */
function hintCmds(h: DiagHint, port: number): { os?: string; cmd: string }[] {
  const env = port === DEFAULT_PORT ? "" : `ARGUS_PORT=${port} `;
  switch (h) {
    case "linuxScript": return [{ cmd: `${env}bash argus-node-linux.sh --open-firewall` }];
    case "linuxUfw": return [{ cmd: `sudo ufw allow ${port}/tcp` }];
    case "linuxFirewalld": return [{ cmd: `sudo firewall-cmd --permanent --add-port=${port}/tcp && sudo firewall-cmd --reload` }];
    case "windowsFirewall": return [{ cmd: `New-NetFirewallRule -DisplayName "Argus rpc-server" -Direction Inbound -Protocol TCP -LocalPort ${port} -Action Allow -Profile Private` }];
    case "restartNode": return [{ os: "Linux / Pi", cmd: `${env}bash argus-node-linux.sh` }, { os: "Windows", cmd: `ggml-rpc-server.exe -H 0.0.0.0 -p ${port} -c` }];
    case "checkIp": return [{ cmd: "hostname -I" }];
    case "updateNode": return [{ os: "Linux / Pi", cmd: `${env}bash argus-node-linux.sh` }];
    default: return [];
  }
}

/** «Проверить связь» modal: opened from the node table / inspector (OFFLINE LAN node), «Найдено в сети», the LAN dialog. */
export default function NetDiag() {
  const target = useCluster((s) => s.netDiag);
  const setNetDiag = useCluster((s) => s.setNetDiag);
  const lang = useLang((s) => s.lang);
  const [addr, setAddr] = useState(target?.address ?? "");
  const [busy, setBusy] = useState(false);
  const [report, setReport] = useState<DiagReport | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [details, setDetails] = useState(false);
  const run_id = useRef(0);

  const parsed = parseNodeAddress(addr);
  const port = report?.port ?? parsed?.port ?? DEFAULT_PORT;
  const T = (key: string, vars: Record<string, string | number | null | undefined> = {}) =>
    tr(key as I18nKey, lang).replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? (k === "port" ? port : "?")));

  async function run(a = addr) {
    const p = parseNodeAddress(a);
    if (!p) { setErr(T("nd.badAddress")); setReport(null); return; }
    const id = ++run_id.current;
    setBusy(true); setErr(null); setReport(null);
    try { const r = await diagnoseNode(p.ip, p.port); if (id === run_id.current) setReport(r); }
    catch (e) { if (id === run_id.current) setErr(String(e)); }
    if (id === run_id.current) setBusy(false);
  }
  // opened for a known node: start right away
  useEffect(() => { if (target?.address && parseNodeAddress(target.address)) run(target.address); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const close = () => { run_id.current++; setNetDiag(null); };
  const stepOf = (id: DiagStepId) => report?.steps.find((s) => s.id === id);
  const good = report?.verdict === "ok";

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60" onClick={close}>
      <div className="max-h-[92vh] w-[640px] max-w-[calc(100vw-2rem)] overflow-y-auto border border-pl-line2 bg-pl-bg1 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex h-9 items-center justify-between border-b border-pl-line bg-pl-bg2 px-3">
          <span className="flex min-w-0 items-center gap-2 truncate text-xs font-semibold uppercase tracking-[0.12em] text-pl-mute">
            <Stethoscope size={13} /> {T("nd.title")}{target?.name ? <span className="truncate normal-case tracking-normal text-pl-text">· {target.name}</span> : null}
          </span>
          <button onClick={close} className="text-pl-dim hover:text-pl-text" aria-label={T("nd.close")}><X size={15} /></button>
        </div>

        <div className="space-y-3 p-4 text-xs">
          <p className="leading-5 text-pl-mute">{T("nd.intro")}</p>
          <div className="flex items-end gap-2">
            <label className="flex-1"><span className="label">{T("nd.address")}</span>
              <input value={addr} autoFocus={!target?.address} onChange={(e) => setAddr(e.target.value)} placeholder="192.168.1.50:50052" spellCheck={false}
                onKeyDown={(e) => { if (e.key === "Enter" && !busy) run(); }}
                className="mt-1 h-8 w-full border border-pl-line2 bg-pl-bg0 px-2 font-mono text-sm text-pl-text outline-none focus:border-pl-blue" />
            </label>
            <button className="btn-primary h-8" disabled={busy || !addr.trim()} onClick={() => run()}>
              {busy ? <Loader2 size={12} className="animate-spin" /> : <Stethoscope size={12} />} {report || err ? T("nd.again") : T("nd.run")}
            </button>
          </div>
          {err && <ErrorBox error={err} />}

          {(busy || report) && (
            <ol className="divide-y divide-pl-line border border-pl-line bg-pl-bg0">
              {STEPS.map((id, i) => <StepRow key={id} n={i + 1} title={T(`nd.step.${id}`)} step={stepOf(id)} busy={busy} T={T} />)}
            </ol>
          )}
          {busy && <div className="text-2xs text-pl-dim">{T("nd.running")}</div>}

          {report && (
            <div className={clsx("border-l-2 p-3", good ? "border-pl-green bg-pl-green/10" : "border-pl-orange bg-pl-orange/10")}>
              <div className={clsx("text-sm font-semibold", good ? "text-pl-green" : "text-pl-orange")}>{T(`nd.v.${report.verdict}.title`)}</div>
              <p className="mt-1 leading-5 text-pl-text">{T(`nd.v.${report.verdict}.text`)}</p>
              {report.hints.length > 0 && (
                <div className="mt-3">
                  <div className="label mb-1">{T("nd.whatToDo")}</div>
                  <ul className="space-y-2.5">
                    {report.hints.map((h) => (
                      <li key={h}>
                        <div className="leading-5 text-pl-mute">{T(`nd.fix.${h}`)}</div>
                        {hintCmds(h, report.port).map((c) => <CopyCmd key={c.cmd} os={c.os} cmd={c.cmd} label={T("nd.copy")} />)}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          )}

          {report && (
            <div>
              <button className="flex items-center gap-1 text-2xs text-pl-dim hover:text-pl-text" onClick={() => setDetails(!details)}>
                {details ? <ChevronDown size={11} /> : <ChevronRight size={11} />} {T("nd.details")}
              </button>
              {details && (
                <pre className="mt-1 overflow-x-auto whitespace-pre-wrap border border-pl-line bg-pl-bg0 p-2 font-mono text-2xs leading-4 text-pl-mute">{[
                  `node ${report.ip}:${report.port} · pc ${report.localIp ?? "—"} · verdict ${report.verdict} · ${report.totalMs} ms`,
                  ...report.steps.map((s) => `${s.id.padEnd(6)} ${s.skipped ? "skip" : s.ok ? "ok  " : "FAIL"} ${s.code}${s.arg ? ` (${s.arg})` : ""} ${s.ms} ms${s.detail ? ` — ${s.detail}` : ""}`),
                ].join("\n")}</pre>
              )}
            </div>
          )}
        </div>

        <div className="flex justify-end gap-2 border-t border-pl-line bg-pl-bg2 px-3 py-2">
          <button className="btn" onClick={close}>{T("nd.close")}</button>
        </div>
      </div>
    </div>
  );
}

function StepRow({ n, title, step, busy, T }: {
  n: number; title: string; step?: DiagStep; busy: boolean;
  T: (k: string, v?: Record<string, string | number | null | undefined>) => string;
}) {
  const state = busy || !step ? "wait" : step.skipped ? "skip" : step.ok ? "ok" : "fail";
  return (
    <li className="flex items-start gap-3 px-3 py-2">
      <span className={clsx("mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border",
        state === "ok" && "border-pl-green bg-pl-green/15 text-pl-green",
        state === "fail" && "border-pl-red bg-pl-red/15 text-pl-red",
        state === "skip" && "border-pl-line2 text-pl-dim",
        state === "wait" && "border-pl-line2 text-pl-blue")}
        title={state}>
        {state === "ok" ? <Check size={12} /> : state === "fail" ? <X size={12} /> : state === "skip" ? <Minus size={12} /> : <Loader2 size={11} className="animate-spin" />}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between gap-2">
          <span className="text-pl-text"><span className="mr-1 font-mono text-pl-dim">{n}.</span>{title}</span>
          {step && !busy && step.ms > 0 && <span className="shrink-0 font-mono text-2xs text-pl-dim">{step.ms} ms</span>}
        </div>
        {step && !busy && <div className={clsx("mt-0.5 leading-4", state === "fail" ? "text-pl-red" : "text-pl-mute")}>{T(`nd.code.${step.id}.${step.code}`, { x: step.arg })}</div>}
      </div>
    </li>
  );
}

function CopyCmd({ os, cmd, label }: { os?: string; cmd: string; label: string }) {
  const [ok, setOk] = useState(false);
  return (
    <div className="mt-1 flex items-center gap-2">
      {os && <span className="w-20 shrink-0 text-2xs text-pl-dim">{os}</span>}
      <code className="min-w-0 flex-1 select-all break-all border border-pl-line2 bg-pl-bg1 px-2 py-1 font-mono text-2xs text-pl-text">{cmd}</code>
      <button className="btn h-6 shrink-0 px-1.5" title={label} aria-label={label}
        onClick={() => { navigator.clipboard?.writeText(cmd).catch(() => {}); setOk(true); setTimeout(() => setOk(false), 1000); }}>
        <Copy size={11} className={ok ? "text-pl-green" : ""} />
      </button>
    </div>
  );
}
