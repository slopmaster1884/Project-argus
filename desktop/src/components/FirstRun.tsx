import { useEffect, useState, type ReactNode } from "react";
import { Check, Copy, ExternalLink, Laptop, Loader2, Monitor, Rocket, Smartphone, Cpu, Star, Usb, Wifi, X } from "lucide-react";
import clsx from "clsx";
import { useCluster } from "../store/cluster";
import { fmt, useLang, useT, type Lang } from "../lib/i18n";
import { featuresGet, featuresSet, openExternal } from "../lib/api";
import { MODELS, bestPick, fitLevel, modelPoolMb, requiredMb } from "../lib/models";
import { deploy } from "../lib/launch";
import { gb } from "../lib/format";
import { useSteady } from "../lib/ui";
import type { FeaturesConfig, ModelEntry } from "../lib/types";
import ErrorBox from "./ErrorBox";

const REPO = "https://github.com/slopmaster1884/Project-argus";
const RELEASES = `${REPO}/releases/latest`;
const doc = (name: "LINUX" | "PC-NODE", lang: Lang) => `${REPO}/blob/main/docs/${name}${lang === "en" ? ".en" : ""}.md`;
const CMD_LINUX = "curl -fsSL https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/install.sh | bash";
const CMD_WINDOWS = "irm https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/argus-node-windows.ps1 -OutFile $env:TEMP\\argus-node.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\\argus-node.ps1";

type Have = "pc" | "android" | "otherPc" | "pi";
const HAVE: { id: Have; icon: typeof Monitor }[] = [
  { id: "pc", icon: Monitor },
  { id: "android", icon: Smartphone },
  { id: "otherPc", icon: Laptop },
  { id: "pi", icon: Cpu },
];
const TOTAL = 5;

/**
 * First-run wizard: language → what devices you have → how to connect them → a model that fits → what's next.
 * Shown once (localStorage argus.firstRunDone), reopened with the ✨ button in the top bar.
 * Reuses the USB wizard, «Добавить по IP», bestPick/fitLevel and deploy() — no own download logic.
 */
export default function FirstRun() {
  const t = useT();
  const { lang, setLang } = useLang();
  const { run, setFirstRun, setWizard, setLanDialog, setTour, setView } = useCluster();
  const [step, setStep] = useState(0);
  const [have, setHave] = useState<Set<Have>>(new Set(["pc"]));
  const close = () => setFirstRun(false);

  useEffect(() => {
    const k = (e: KeyboardEvent) => { if (e.key === "Escape") setFirstRun(false); };
    window.addEventListener("keydown", k); return () => window.removeEventListener("keydown", k);
  }, [setFirstRun]);

  function pickLang(l: Lang) {
    setLang(l);
    // the UI language lives in argus-features.json (features_set merges partial patches)
    featuresGet().then((f) => f && featuresSet({ lang: l } as unknown as FeaturesConfig)).catch(() => {});
  }
  function toggle(id: Have) {
    setHave((cur) => {
      const n = new Set(cur);
      if (n.has(id)) n.delete(id); else n.add(id);
      if (id === "pc" && n.has("pc")) return new Set<Have>(["pc"]);   // «только этот ПК» excludes the rest
      if (id !== "pc") n.delete("pc");
      return n.size ? n : new Set<Have>(["pc"]);
    });
  }

  // child dialogs (USB wizard, add by IP) open on top; the wizard stays where it was
  const openUsb = () => setWizard(true);
  const openLan = () => setLanDialog(true);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
      <div className="flex max-h-[92vh] w-[680px] max-w-[calc(100vw-2rem)] flex-col border border-pl-line2 bg-pl-bg1 shadow-2xl">
        <div className="flex h-9 shrink-0 items-center justify-between border-b border-pl-line bg-pl-bg2 px-3">
          <span className="text-xs font-semibold uppercase tracking-[0.12em] text-pl-mute">{t("fr.title")} · {fmt(t("fr.step"), { n: step + 1, total: TOTAL })}</span>
          <button onClick={close} title={t("fr.close")} className="text-pl-dim hover:text-pl-text"><X size={15} /></button>
        </div>
        <div className="flex shrink-0 gap-1 px-4 pt-3">{Array.from({ length: TOTAL }, (_, j) => <span key={j} className={clsx("h-1 flex-1", j <= step ? "bg-pl-blue" : "bg-pl-bg4")} />)}</div>

        <div className="min-h-0 flex-1 overflow-y-auto p-5">
          {step === 0 && (
            <>
              <h2 className="text-lg font-medium text-pl-text">{t("fr.lang.title")}</h2>
              <div className="mt-4 grid grid-cols-2 gap-3">
                {(["ru", "en"] as Lang[]).map((l) => (
                  <button key={l} onClick={() => pickLang(l)}
                    className={clsx("flex h-16 items-center justify-center gap-2 rounded border text-base", lang === l ? "border-pl-blue bg-pl-blue/10 text-pl-text" : "border-pl-line2 text-pl-mute hover:bg-pl-bg3")}>
                    {lang === l && <Check size={16} className="text-pl-blue" />} {l === "ru" ? "Русский" : "English"}
                  </button>
                ))}
              </div>
              <p className="mt-3 text-xs text-pl-dim">{t("fr.lang.desc")}</p>
            </>
          )}

          {step === 1 && (
            <>
              <h2 className="text-lg font-medium text-pl-text">{t("fr.have.title")}</h2>
              <p className="mt-1 text-xs text-pl-mute">{t("fr.have.desc")}</p>
              <div className="mt-4 space-y-2">
                {HAVE.map(({ id, icon: I }) => {
                  const on = have.has(id);
                  return (
                    <button key={id} onClick={() => toggle(id)}
                      className={clsx("flex w-full items-center gap-3 rounded border px-3 py-2.5 text-left", on ? "border-pl-blue bg-pl-blue/10" : "border-pl-line2 hover:bg-pl-bg3")}>
                      <span className={clsx("flex h-5 w-5 shrink-0 items-center justify-center rounded-sm border", on ? "border-pl-blue bg-pl-blue2 text-white" : "border-pl-line2")}>{on && <Check size={13} />}</span>
                      <I size={18} className={on ? "text-pl-blue" : "text-pl-dim"} />
                      <span className="min-w-0">
                        <span className="block text-sm text-pl-text">{t(`fr.have.${id}` as const)}</span>
                        <span className="block text-2xs text-pl-dim">{t(`fr.have.${id}Desc` as const)}</span>
                      </span>
                    </button>
                  );
                })}
              </div>
            </>
          )}

          {step === 2 && <HowTo have={have} lang={lang} openUsb={openUsb} openLan={openLan} />}

          {step === 3 && <PickModel onStarted={() => setStep(4)} openModels={() => { setView("models"); close(); }} />}

          {step === 4 && (
            <>
              <h2 className="text-lg font-medium text-pl-text">{t("fr.done.title")}</h2>
              <div className="mt-3">
                {run.status === "loading" && <Status icon={<Loader2 size={14} className="animate-spin text-pl-orange" />} text={t("fr.done.loading")} />}
                {run.status === "ready" && <Status icon={<Check size={14} className="text-pl-green" />} text={t("fr.done.ready")} />}
                {(run.status === "idle" || run.status === "broken") && <Status icon={<Rocket size={14} className="text-pl-blue" />} text={t("fr.done.idle")} />}
                {run.status === "error" && <><Status icon={<X size={14} className="text-pl-red" />} text={t("fr.done.error")} /><ErrorBox error={run.message} className="mt-2" /></>}
              </div>
              <div className="label mt-5">{t("fr.done.next")}</div>
              <ul className="mt-1.5 list-disc space-y-1 pl-5 text-xs leading-5 text-pl-mute">
                <li>{t("fr.done.n1")}</li><li>{t("fr.done.n2")}</li><li>{t("fr.done.n3")}</li>
              </ul>
              <div className="mt-5 flex flex-wrap gap-2">
                <button className="btn-primary h-9 px-4 text-sm" onClick={() => { setView("chat"); close(); }}>{t("fr.done.chat")}</button>
                {run.status !== "ready" && run.status !== "loading" && <button className="btn h-9" onClick={() => { setView("models"); close(); }}>{t("fr.done.models")}</button>}
                <button className="btn h-9" onClick={() => { close(); setTour(true); }}>{t("fr.done.tour")}</button>
              </div>
            </>
          )}
        </div>

        <div className="flex shrink-0 items-center gap-2 border-t border-pl-line bg-pl-bg2 px-3 py-2">
          {step < TOTAL - 1 && <button className="text-2xs text-pl-dim hover:text-pl-text" onClick={close}>{t("fr.skip")}</button>}
          <button className="btn ml-auto" disabled={step === 0} onClick={() => setStep(step - 1)}>{t("fr.back")}</button>
          {step < TOTAL - 1
            ? <button className="btn-primary" onClick={() => setStep(step + 1)}>{t("fr.next")}</button>
            : <button className="btn-primary" onClick={close}>{t("fr.close")}</button>}
        </div>
      </div>
    </div>
  );
}

const Status = ({ icon, text }: { icon: ReactNode; text: string }) => (
  <div className="flex items-start gap-2 border border-pl-line bg-pl-bg0 p-3 text-sm leading-5 text-pl-text"><span className="mt-0.5 shrink-0">{icon}</span>{text}</div>
);

function CopyCmd({ cmd }: { cmd: string }) {
  const t = useT();
  const [ok, setOk] = useState(false);
  return (
    <div className="mt-1.5 flex items-stretch gap-2">
      <code className="min-w-0 flex-1 select-all break-all border border-pl-line2 bg-pl-bg0 px-2 py-1.5 font-mono text-2xs text-pl-text">{cmd}</code>
      <button className="btn h-auto shrink-0" title={t("fr.copy")} onClick={() => { navigator.clipboard?.writeText(cmd); setOk(true); setTimeout(() => setOk(false), 1200); }}>
        {ok ? <Check size={12} className="text-pl-green" /> : <Copy size={12} />} {t("fr.copy")}
      </button>
    </div>
  );
}

const Link = ({ href, children }: { href: string; children: ReactNode }) => (
  <button className="inline-flex items-center gap-1 text-2xs text-pl-blue hover:underline" onClick={() => openExternal(href).catch(() => {})}>
    <ExternalLink size={11} /> {children}
  </button>
);

const Section = ({ title, icon, children }: { title: string; icon: ReactNode; children: ReactNode }) => (
  <div className="border border-pl-line bg-pl-bg1">
    <div className="flex items-center gap-2 border-b border-pl-line bg-pl-bg2 px-3 py-1.5 text-xs font-medium text-pl-text">{icon} {title}</div>
    <div className="space-y-1.5 p-3 text-xs leading-5 text-pl-mute">{children}</div>
  </div>
);

function HowTo({ have, lang, openUsb, openLan }: { have: Set<Have>; lang: Lang; openUsb: () => void; openLan: () => void }) {
  const t = useT();
  const snapshot = useCluster((s) => s.snapshot);
  const [os, setOs] = useState<"windows" | "linux">("windows");
  const connected = snapshot?.nodes.filter((n) => n.stage === "connected" && n.enabled).length ?? 0;
  const found = snapshot?.discovered.length ?? 0;
  const network = have.has("otherPc") || have.has("pi") || have.has("android");
  return (
    <>
      <h2 className="text-lg font-medium text-pl-text">{t("fr.how.title")}</h2>
      <div className="mt-1 flex items-center gap-2 font-mono text-2xs text-pl-dim">
        <span className={connected ? "text-pl-green" : ""}>● {fmt(t("fr.how.connected"), { n: connected })}</span>
        {found > 0 && <span className="text-pl-cyan">· {fmt(t("fr.how.found"), { n: found })}</span>}
      </div>
      <div className="mt-3 space-y-3">
        {have.has("pc") && <Section title={t("fr.have.pc")} icon={<Monitor size={13} />}><p>{t("fr.how.pc")}</p></Section>}

        {have.has("android") && (
          <>
            <Section title={t("fr.how.usbTitle")} icon={<Usb size={13} />}>
              <ol className="list-decimal space-y-1 pl-4"><li>{t("fr.how.usb1")}</li><li>{t("fr.how.usb2")}</li><li>{t("fr.how.usb3")}</li></ol>
              <button className="btn-primary mt-1" onClick={openUsb}><Usb size={12} /> {t("fr.how.usbBtn")}</button>
            </Section>
            <Section title={t("fr.how.wifiTitle")} icon={<Wifi size={13} />}>
              <ol className="list-decimal space-y-1 pl-4"><li>{t("fr.how.wifi1")}</li><li>{t("fr.how.wifi2")}</li><li>{t("fr.how.wifi3")}</li></ol>
              <Link href={RELEASES}>{t("fr.how.releases")} (Argus-Node.apk)</Link>
            </Section>
          </>
        )}

        {have.has("otherPc") && (
          <Section title={os === "windows" ? t("fr.how.winTitle") : t("fr.how.linuxTitle")} icon={<Laptop size={13} />}>
            <div className="flex gap-1">
              {(["windows", "linux"] as const).map((o) => (
                <button key={o} onClick={() => setOs(o)} className={clsx("rounded border px-2.5 py-0.5 text-2xs", os === o ? "border-pl-blue text-pl-text" : "border-pl-line2 text-pl-dim hover:bg-pl-bg3")}>{o === "windows" ? "Windows" : "Linux"}</button>
              ))}
            </div>
            {os === "windows" ? (
              <><p>{t("fr.how.win1")}</p><CopyCmd cmd={CMD_WINDOWS} /><p>{t("fr.how.win2")}</p></>
            ) : (
              <><p>{t("fr.how.linux1")}</p><CopyCmd cmd={CMD_LINUX} /></>
            )}
            <p>{t("fr.how.addNode")}</p>
            <div className="flex flex-wrap items-center gap-3">
              <button className="btn" onClick={openLan}><Wifi size={12} /> {t("fr.how.addByIp")}</button>
              <Link href={doc("PC-NODE", lang)}>{t("fr.how.docs")}</Link>
            </div>
          </Section>
        )}

        {have.has("pi") && (
          <Section title={t("fr.how.piTitle")} icon={<Cpu size={13} />}>
            <p>{t("fr.how.pi1")}</p><CopyCmd cmd={CMD_LINUX} />
            <p>{t("fr.how.addNode")}</p>
            <div className="flex flex-wrap items-center gap-3">
              <button className="btn" onClick={openLan}><Wifi size={12} /> {t("fr.how.addByIp")}</button>
              <Link href={doc("LINUX", lang)}>{t("fr.how.docs")}</Link>
            </div>
          </Section>
        )}
      </div>
      {network && <p className="mt-3 border-l-2 border-pl-orange bg-pl-orange/10 p-2 text-2xs text-pl-orange">{t("fr.how.homeOnly")}</p>}
      {network && <p className="mt-2 text-2xs text-pl-dim">{t("fr.how.later")}</p>}
    </>
  );
}

const rank = (m: ModelEntry) => (m.score ?? 0) + (m.moe ? 15 : 0) + (m.tools ? 2 : 0); // same order as bestPick

function PickModel({ onStarted, openModels }: { onStarted: () => void; openModels: () => void }) {
  const t = useT();
  const { snapshot, ctx, run } = useCluster();
  const pool = useSteady(modelPoolMb(snapshot));
  const best = bestPick(pool, ctx);
  const alts = MODELS.filter((m) => !m.vision && m.id !== best?.id && fitLevel(m, pool, ctx) === "fits").sort((a, b) => rank(b) - rank(a)).slice(0, 2);
  const loading = run.status === "loading";
  const start = (m: ModelEntry) => { void deploy(m, { goChat: false }); onStarted(); };
  const Row = ({ m, star }: { m: ModelEntry; star?: boolean }) => (
    <div className={clsx("flex items-center gap-3 border p-3", star ? "border-pl-blue bg-pl-blue/5" : "border-pl-line")}>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5 text-sm text-pl-text">{star && <Star size={13} className="fill-pl-gold text-pl-gold" />}{m.name}</div>
        <div className="font-mono text-2xs text-pl-dim">{m.params} · {fmt(t("fr.model.need"), { gb: gb(requiredMb(m, ctx)) })}{m.moe ? " · MoE" : ""}</div>
        {m.note && <div className="text-2xs text-pl-mute">{m.note}</div>}
      </div>
      <button className={star ? "btn-primary h-8" : "btn h-8"} disabled={loading} onClick={() => start(m)}><Rocket size={12} /> {t("fr.model.start")}</button>
    </div>
  );
  return (
    <>
      <h2 className="text-lg font-medium text-pl-text">{t("fr.model.title")}</h2>
      <p className="mt-1 text-xs text-pl-mute">{fmt(t("fr.model.desc"), { pool: gb(pool) })}</p>
      {loading && <div className="mt-3 flex items-center gap-2 text-xs text-pl-orange"><Loader2 size={12} className="animate-spin" /> {fmt(t("fr.model.loading"), { name: run.model.name })}</div>}
      {run.status === "ready" && <div className="mt-3 flex items-center gap-2 text-xs text-pl-green"><Check size={12} /> {fmt(t("fr.model.ready"), { name: run.model.name })}</div>}
      <div className="mt-3 space-y-2">
        {best ? (
          <>
            <div className="label">{t("fr.model.best")}</div>
            <Row m={best} star />
            {alts.length > 0 && <div className="label pt-2">{t("fr.model.alt")}</div>}
            {alts.map((m) => <Row key={m.id} m={m} />)}
          </>
        ) : <div className="border border-pl-line bg-pl-bg0 p-3 text-xs text-pl-mute">{t("fr.model.empty")}</div>}
      </div>
      <div className="mt-3 flex items-center justify-between gap-3">
        <span className="text-2xs text-pl-dim">{t("fr.model.grow")}</span>
        <button className="shrink-0 text-2xs text-pl-blue hover:underline" onClick={openModels}>{t("fr.model.more")} →</button>
      </div>
    </>
  );
}
