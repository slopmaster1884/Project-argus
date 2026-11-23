import { Check, Palette, X } from "lucide-react";
import clsx from "clsx";
import { THEMES, useAppearance, type Bg, type Glass, type Motion } from "../../lib/theme";
import { useT, type I18nKey } from "../../lib/i18n";

/** Appearance settings: theme, glass level, background, animations (incl. «без анимаций» and OS reduce-motion). */
export default function AppearanceDialog({ onClose, onSplash }: { onClose: () => void; onSplash: () => void }) {
  const a = useAppearance();
  const t = useT();
  const seg = <T extends string>(k: string, vals: T[], cur: T, on: (v: T) => void) => (
    <div className="flex flex-wrap gap-1">
      {vals.map((v) => (
        <button key={v} onClick={() => on(v)} className={clsx("h-7 rounded border px-2.5 text-xs", cur === v ? "border-pl-blue bg-pl-blue2/25 text-pl-text" : "border-pl-line2/70 bg-pl-bg3 text-pl-mute hover:text-pl-text")}>
          {t(`${k}.${v}` as I18nKey)}
        </button>
      ))}
    </div>
  );
  const chk = (k: "splash" | "fxNotify" | "fxIncident") => (
    <label className="flex cursor-pointer items-center gap-2 text-xs text-pl-text">
      <input type="checkbox" className="accent-[rgb(var(--pl-blue2))]" checked={a[k]} onChange={(e) => a.set({ [k]: e.target.checked })} />
      {t(`ap.${k}` as I18nKey)}
    </label>
  );
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div role="dialog" aria-label={t("ap.title")} onClick={(e) => e.stopPropagation()}
        className="anim-pop w-[560px] max-w-[calc(100vw-2rem)] overflow-hidden rounded-xl border border-pl-line2/70 bg-pl-bg1 shadow-2xl">
        <div className="panel-head"><span className="flex items-center gap-2"><Palette size={13} />{t("ap.title")}</span>
          <button onClick={onClose} className="text-pl-dim hover:text-pl-text"><X size={13} /></button></div>
        <div className="flex flex-col gap-4 p-4">
          <section>
            <div className="label mb-2">{t("ap.theme")}</div>
            <div className="grid grid-cols-4 gap-2">
              {THEMES.map((th) => (
                <button key={th.id} onClick={() => a.set({ theme: th.id })}
                  className={clsx("group relative overflow-hidden rounded-lg border text-left", a.theme === th.id ? "border-pl-blue glow" : "border-pl-line2/60 hover:border-pl-line2")}>
                  <div className="h-16 bg-cover bg-center" style={{ backgroundImage: `url(/theme/bg-${th.id}.webp)` }} />
                  <div className="flex items-center gap-1.5 bg-pl-bg2 px-2 py-1.5 text-2xs text-pl-text">
                    <span className="h-2.5 w-2.5 rounded-full border border-white/30" style={{ background: th.swatch[1] }} />
                    <span className="truncate">{t(`ap.theme.${th.id}` as I18nKey)}</span>
                    {a.theme === th.id && <Check size={11} className="ml-auto text-pl-blue" />}
                  </div>
                  {th.id === "green" && <span className="absolute right-1 top-1 rounded bg-black/60 px-1 text-[9px] uppercase text-white/80">{t("ap.default")}</span>}
                </button>
              ))}
            </div>
          </section>
          <section><div className="label mb-2">{t("ap.glass")}</div>{seg<Glass>("ap.glass", ["off", "low", "mid", "high"], a.glass, (glass) => a.set({ glass }))}</section>
          <section><div className="label mb-2">{t("ap.bg")}</div>{seg<Bg>("ap.bg", ["image", "drift", "plain", "window"], a.bg, (bg) => a.set({ bg }))}
            {a.bg === "window" && <p className="mt-1.5 text-2xs leading-4 text-pl-dim">{t("ap.bg.windowHint")}</p>}</section>
          <section><div className="label mb-2">{t("ap.motion")}</div>{seg<Motion>("ap.motion", ["auto", "full", "off"], a.motion, (motion) => a.set({ motion }))}
            <div className={clsx("mt-3 flex flex-col gap-2", a.motion === "off" && "pointer-events-none opacity-40")}>{chk("splash")}{chk("fxNotify")}{chk("fxIncident")}</div></section>
        </div>
        <div className="flex flex-wrap items-center gap-2 border-t border-pl-line/70 bg-pl-bg2 px-4 py-2.5">
          <button className="btn" onClick={onSplash}>▶ {t("ap.pv.splash")}</button>
          <button className="btn" onClick={() => window.dispatchEvent(new CustomEvent("argus-fx-preview", { detail: "incident" }))}>▶ {t("fx.incident")}</button>
          <button className="btn ml-auto" onClick={a.reset}>{t("ap.reset")}</button>
          <button className="btn-primary" onClick={onClose}>{t("ap.close")}</button>
        </div>
      </div>
    </div>
  );
}
