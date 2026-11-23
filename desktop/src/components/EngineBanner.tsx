import { useState } from "react";
import { Flame, Loader2, RotateCw, TriangleAlert, Zap } from "lucide-react";
import { useCluster } from "../store/cluster";
import { restartEngine } from "../lib/api";
import { humanizeError } from "../lib/errors";
import { useT } from "../lib/i18n";
import { Details } from "./ErrorBox";
import { toastError } from "../lib/errors";

/** Engine problems + the "Перезапустить движок" button. Shown in Chat and Devices. */
export default function EngineBanner({ compact }: { compact?: boolean }) {
  const { snapshot, run, pushToast } = useCluster();
  const [busy, setBusy] = useState(false);
  const t = useT();
  const e = snapshot?.engine;
  if (!e) return null;
  const broken = e.status === "broken" || run.status === "broken";
  const hint = !broken && e.status === "ready" && e.newNodes;
  const warming = !broken && e.status === "ready" && e.warming;
  if (!broken && !hint && !warming) return null;
  if (warming && !hint) return (
    <div className={`flex items-center gap-3 border-l-2 border-pl-cyan bg-pl-cyan/10 px-3 py-2 text-xs ${compact ? "" : "mx-3 mt-3"}`}>
      <Flame size={14} className="shrink-0 text-pl-cyan" />
      <div className="min-w-0 flex-1 leading-5">
        <span className="font-semibold text-pl-cyan">Прогрев…</span>{" "}
        <span className="text-pl-text">Модель загружена и один раз прогоняет системный промпт чата — так первый ответ придёт быстрее. Писать уже можно.</span>
      </div>
      <Loader2 size={12} className="shrink-0 animate-spin text-pl-cyan" />
    </div>
  );

  async function restart() {
    setBusy(true);
    try { await restartEngine(); pushToast("info", "Движок перезапускается с текущим набором нод…"); }
    catch (err) { toastError(err); }
    setBusy(false);
  }
  const reason = e.reason ?? (run.status === "broken" ? run.reason : "");
  return (
    <div className={`flex items-start gap-3 border-l-2 px-3 py-2 text-xs ${broken ? "border-pl-orange bg-pl-orange/10" : "border-pl-cyan bg-pl-cyan/10"} ${compact ? "" : "mx-3 mt-3"}`}>
      {broken ? <TriangleAlert size={14} className="mt-0.5 shrink-0 text-pl-orange" /> : <Zap size={14} className="mt-0.5 shrink-0 text-pl-cyan" />}
      <div className="min-w-0 flex-1 leading-5">
        {broken ? (
          <>
            <div className="font-semibold text-pl-orange">Движок остановлен</div>
            <Reason reason={reason} t={t} />
            {e.pendingRestart && <div className="mt-0.5 flex items-center gap-1.5 font-mono text-2xs text-pl-mute"><Loader2 size={10} className="animate-spin" /> автоперезапуск, когда кластер стабилизируется (3 с без изменений)</div>}
          </>
        ) : (
          <div className="text-pl-text">В кластере появилась новая нода. Запущенная модель её не использует — перезапустите движок, чтобы распределить слои заново.</div>
        )}
      </div>
      {e.canRestart && (
        <button className="btn shrink-0" disabled={busy} onClick={restart}>
          {busy ? <Loader2 size={12} className="animate-spin" /> : <RotateCw size={12} />} Перезапустить движок
        </button>
      )}
    </div>
  );
}

/** «Движок не запустился: cudaMalloc failed: out of memory» → «Не хватает памяти» + what to do, raw under «Подробнее». */
function Reason({ reason, t }: { reason: string; t: ReturnType<typeof useT> }) {
  const h = humanizeError(reason, t);
  // node-disconnect reasons etc. are already plain Russian: show them as they are
  if (!h.kind || h.kind === "engine") return <><div className="text-pl-text">{reason}</div>{h.kind && <div className="text-pl-mute">{h.hint}</div>}</>;
  return (
    <>
      <div className="text-pl-text">{h.title}. {h.hint}</div>
      <Details raw={h.raw} className="mt-0.5" />
    </>
  );
}
