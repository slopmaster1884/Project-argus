import { useEffect } from "react";
import { BookOpen, Boxes, ListTodo, Columns3, MessageSquareText, Network, Plug, Sparkles, Usb } from "lucide-react";
import clsx from "clsx";
import { useCluster, type View } from "../store/cluster";
import { featuresGet } from "../lib/api";
import { useLang, useT, type I18nKey } from "../lib/i18n";

const items: { id: View; label: I18nKey; icon: typeof Boxes }[] = [
  { id: "chat", label: "nav.chat", icon: MessageSquareText },
  { id: "devices", label: "nav.devices", icon: Network },
  { id: "models", label: "nav.models", icon: Boxes },
  { id: "api", label: "nav.api", icon: Plug },
  { id: "parallel", label: "nav.parallel", icon: Columns3 },
  { id: "features", label: "nav.features", icon: Sparkles },
  { id: "queue", label: "nav.queue", icon: ListTodo },
  { id: "knowledge", label: "nav.knowledge", icon: BookOpen },
];

export default function NavRail() {
  const { view, setView, setWizard } = useCluster();
  const t = useT();
  // UI language lives in argus-features.json
  useEffect(() => { featuresGet().then((f) => { if (f && (f.lang === "ru" || f.lang === "en")) useLang.getState().setLang(f.lang); }).catch(() => {}); }, []);
  return (
    <aside className="flex w-14 shrink-0 flex-col items-center gap-1 border-r border-pl-line/70 bg-pl-bg1 px-1.5 py-2 lg:w-[72px]">
      {items.map(({ id, label: key, icon: Icon }) => { const label = t(key); return (
        <button key={id} data-nav={id} aria-label={label} onClick={() => setView(id)} title={id === "parallel" ? t("nav.parallelHint") : label}
          className={clsx("group relative flex h-11 w-full flex-col items-center justify-center gap-0.5 rounded-lg text-[10px] transition-all duration-150 lg:h-[52px]",
            view === id ? "bg-pl-blue/15 text-pl-text shadow-[inset_0_0_0_1px_rgb(var(--pl-blue)/.45),0_0_18px_-6px_rgb(var(--accent-glow)/.8)]" : "text-pl-dim hover:bg-pl-bg3 hover:text-pl-text")}>
          {view === id && <span className="absolute -left-1.5 top-1/2 h-6 w-[3px] -translate-y-1/2 rounded-r bg-pl-blue shadow-[0_0_10px_rgb(var(--accent-glow))]" />}
          <Icon size={18} strokeWidth={1.7} className={clsx("transition-transform duration-150 group-hover:scale-110", view === id && "text-pl-blue drop-shadow-[0_0_6px_rgb(var(--accent-glow)/.8)]")} />
          <span className="hidden max-w-full truncate px-0.5 leading-tight lg:block">{label}</span>
        </button>
      ); })}
      <div className="mt-auto">
        <button onClick={() => setWizard(true)} title={t("nav.connect")}
          className="flex h-10 w-10 items-center justify-center rounded-xl border border-pl-blue/50 bg-pl-blue/10 text-pl-blue transition-all hover:bg-pl-blue/20 hover:shadow-[0_0_18px_-4px_rgb(var(--accent-glow))]">
          <Usb size={17} />
        </button>
      </div>
    </aside>
  );
}
