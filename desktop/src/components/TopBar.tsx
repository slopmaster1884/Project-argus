import { useEffect, useState } from "react";
import { ChevronRight, CircleHelp, Hexagon, Info, Palette, Sparkles } from "lucide-react";
import { useAppearanceUi } from "../lib/theme";
import { useT, type I18nKey } from "../lib/i18n";
import clsx from "clsx";
import { useCluster } from "../store/cluster";
import { gb } from "../lib/format";

const titleKey: Record<string, I18nKey> = { chat: "nav.chat", devices: "nav.devices", models: "nav.models", api: "nav.api", parallel: "nav.parallel", features: "nav.features", queue: "nav.queue", knowledge: "nav.knowledge" };

export default function TopBar() {
  const { view, snapshot, run, setTour, setFirstRun, setAbout, update, setUpdateDialog } = useCluster();
  const t = useT();
  const upd = update?.available && update.latest ? update.latest.version : null;
  const warming = run.status === "ready" && !!snapshot?.engine.warming;
  const [now, setNow] = useState(new Date());
  useEffect(() => { const t = setInterval(() => setNow(new Date()), 1000); return () => clearInterval(t); }, []);
  const online = (snapshot?.nodes.filter((n) => n.stage === "connected" && n.enabled).length ?? 0) + Math.max(1, snapshot?.gpus.filter((g) => g.enabled).length ?? 1);

  return (
    <header className="flex h-12 min-w-0 items-center gap-3 overflow-hidden whitespace-nowrap border-b border-pl-line/70 bg-pl-bg2 pl-4 pr-3 xl:pr-4">
      <div className="flex shrink-0 items-center gap-2">
        <Hexagon size={20} className="fill-pl-blue2 text-pl-blue drop-shadow-[0_0_6px_rgb(var(--accent-glow)/.8)]" strokeWidth={1.5} />
        <span className="bg-gradient-to-r from-pl-text to-pl-blue bg-clip-text text-[14px] font-bold tracking-[0.22em] text-transparent">ARGUS</span>
        <span className="hidden text-2xs text-pl-dim xl:inline">LOCAL COMPUTE</span>
      </div>
      <div className="ml-1 flex min-w-0 items-center gap-1 text-xs text-pl-mute xl:ml-3">
                <span className="hidden xl:inline">argus-cluster</span><ChevronRight size={12} className="hidden shrink-0 text-pl-dim xl:block" />
        <span className="truncate rounded-full bg-pl-bg3 px-2.5 py-0.5 font-medium text-pl-text" title={t(titleKey[view] ?? "nav.chat")}>{t(titleKey[view] ?? "nav.chat")}</span>
      </div>

      <div className="ml-auto flex min-w-0 items-center gap-3 font-mono text-2xs xl:gap-5">
        <Stat k={t("tb.nodes")} v={`${online}`} className="hidden lg:flex" />
        <Stat k={t("tb.pool")} v={`${gb(snapshot?.totalMb ?? 0)} GB`} className="hidden lg:flex" />
        <Stat k={t("tb.alloc")} v={`${gb(snapshot?.usableMb ?? 0)} GB`} className="hidden xl:flex" />
        <span className={clsx("tag block min-w-0 max-w-[260px] truncate border py-0.5",
          warming ? "animate-blink border-pl-cyan/60 text-pl-cyan" :
          run.status === "ready" ? "border-pl-green/50 text-pl-green" :
          run.status === "loading" ? "animate-blink border-pl-orange/50 text-pl-orange" :
          run.status === "error" ? "border-pl-red/50 text-pl-red" :
          run.status === "broken" ? "animate-blink border-pl-orange/60 text-pl-orange" : "border-pl-line2 text-pl-dim")}
          title={run.status === "broken" ? run.reason : warming ? "Модель загружена и разогревает кэш системного промпта — первый ответ будет быстрее" : run.status === "idle" ? undefined : run.status === "error" ? run.message : run.model.name}>
          ● {run.status === "idle" ? t("tb.idle") : run.status === "error" ? t("tb.error") : run.status === "broken" ? `${run.model.name} · ОСТАНОВЛЕН` : warming ? `${run.model.name} · Прогрев…` : `${run.model.name}`}
        </span>
        <span className="hidden text-pl-dim xl:inline">{now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false })}</span>
        {upd && (
          <button title="Доступно обновление — нажмите, чтобы решить" onClick={() => setUpdateDialog(true)}
            className="tag shrink-0 border border-pl-green/60 text-pl-green hover:bg-pl-green/10">⬆ {upd}</button>
        )}
        <button title={t("ap.open")} onClick={() => useAppearanceUi.getState().setOpen(true)} className="icon-btn text-pl-blue">
          <Palette size={13} />
        </button>
        <button title="О программе · обновления" onClick={() => setAbout(true)} className="icon-btn">
          <Info size={13} />
        </button>
        <button title={t("fr.reopen")} onClick={() => setFirstRun(true)} className="icon-btn text-pl-blue">
          <Sparkles size={13} />
        </button>
        <button title="Обучение" onClick={() => setTour(true)} className="icon-btn">
          <CircleHelp size={13} />
        </button>
      </div>
    </header>
  );
}

const Stat = ({ k, v, className }: { k: string; v: string; className?: string }) => (
  <span className={clsx("shrink-0 items-center gap-1.5 rounded-full border border-pl-line/60 bg-pl-bg3 px-2.5 py-0.5", className ?? "flex")}><span className="uppercase tracking-wide text-pl-dim">{k}</span><span className="font-semibold text-pl-text">{v}</span></span>
);
