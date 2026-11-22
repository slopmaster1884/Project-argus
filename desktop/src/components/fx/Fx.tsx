import { useEffect, useRef, useState } from "react";
import { TriangleAlert } from "lucide-react";
import { useCluster } from "../../store/cluster";
import { animSrc, motionOff, useAppearance } from "../../lib/theme";
import { useT } from "../../lib/i18n";

type Incident = { id: number; title: string; text: string };
const HOT_C = 45; // phone battery/SoC temperature that counts as «перегрев»

/**
 * Theme animations for events:
 *  - notification: a small glass bubble with the theme clip pops next to the toasts (info / ok);
 *  - incident: a short full-screen flash of the clip with a red vignette — a node dropped out,
 *    a device overheated, an error toast, or the engine broke.
 * Respects Appearance → Animations (off / OS reduce-motion) and the two fx toggles.
 */
export default function Fx() {
  const { theme, fxNotify, fxIncident } = useAppearance();
  const t = useT();
  const toasts = useCluster((s) => s.toasts);
  const snapshot = useCluster((s) => s.snapshot);
  const runStatus = useCluster((s) => s.run.status);
  const [pulse, setPulse] = useState<number | null>(null);
  const [incident, setIncident] = useState<Incident | null>(null);
  const seen = useRef(new Set<string>());
  const online = useRef<Map<string, string> | null>(null);
  const hot = useRef(new Set<string>());
  const lastRun = useRef(runStatus);

  const fire = (title: string, text: string) => {
    if (!fxIncident || motionOff()) return;
    const id = Date.now();
    setIncident({ id, title, text });
    setTimeout(() => setIncident((c) => (c?.id === id ? null : c)), 2600);
  };

  // toasts → notification pulse or incident
  useEffect(() => {
    for (const x of toasts) {
      if (seen.current.has(x.id)) continue;
      seen.current.add(x.id);
      if (x.kind === "error") fire(t("fx.incident"), x.text);
      else if (fxNotify && !motionOff()) { const id = Date.now(); setPulse(id); setTimeout(() => setPulse((p) => (p === id ? null : p)), 2400); }
    }
  }, [toasts]); // eslint-disable-line react-hooks/exhaustive-deps

  // snapshot → node lost / overheating
  useEffect(() => {
    if (!snapshot) return;
    const now = new Map(snapshot.nodes.filter((n) => n.stage === "connected" && n.enabled).map((n) => [n.id, n.name] as const));
    if (online.current) for (const [id, name] of online.current) if (!now.has(id)) { fire(t("fx.nodeLost"), name); break; }
    online.current = now;
    for (const n of snapshot.nodes) {
      const isHot = (n.tempC ?? 0) >= HOT_C;
      if (isHot && !hot.current.has(n.id)) { hot.current.add(n.id); fire(t("fx.hot"), `${n.name}: ${Math.round(n.tempC!)} °C`); }
      else if (!isHot) hot.current.delete(n.id);
    }
  }, [snapshot]); // eslint-disable-line react-hooks/exhaustive-deps

  // engine broke / failed
  useEffect(() => {
    if (runStatus !== lastRun.current && (runStatus === "error" || runStatus === "broken")) fire(t("fx.incident"), runStatus === "error" ? "ENGINE ERROR" : "ENGINE STOPPED");
    lastRun.current = runStatus;
  }, [runStatus]); // eslint-disable-line react-hooks/exhaustive-deps

  // preview from Appearance dialog
  useEffect(() => {
    const h = (e: Event) => {
      const k = (e as CustomEvent<string>).detail;
      if (k === "incident") { const id = Date.now(); setIncident({ id, title: t("fx.nodeLost"), text: "Pixel 8 · 192.168.1.42" }); setTimeout(() => setIncident((c) => (c?.id === id ? null : c)), 2600); }
      else { const id = Date.now(); setPulse(id); setTimeout(() => setPulse((p) => (p === id ? null : p)), 2400); }
    };
    window.addEventListener("argus-fx-preview", h);
    return () => window.removeEventListener("argus-fx-preview", h);
  }, [t]);

  const src = animSrc(theme);
  return (
    <>
      {pulse && (
        <div key={pulse} className="glass anim-pop anim-ring pointer-events-none fixed bottom-8 right-[404px] z-[61] hidden h-16 w-28 overflow-hidden rounded-lg border border-pl-blue/50 bg-pl-bg2 sm:block">
          <video className="argus-anim h-full w-full object-cover" src={src} autoPlay muted loop playsInline onError={(e) => { (e.currentTarget as HTMLVideoElement).style.display = "none"; }} />
          <div className="absolute inset-0" style={{ background: "linear-gradient(180deg, transparent 40%, rgb(var(--accent-glow) / .35))" }} />
        </div>
      )}
      {incident && (
        <div key={incident.id} className="pointer-events-none fixed inset-0 z-[90]" style={{ animation: "argus-incident 2.6s ease both" }}>
          <video className="argus-anim absolute inset-0 h-full w-full object-cover opacity-40 mix-blend-screen" src={src} autoPlay muted loop playsInline onError={(e) => { (e.currentTarget as HTMLVideoElement).style.display = "none"; }} />
          <div className="absolute inset-0" style={{ background: "radial-gradient(ellipse at center, transparent 35%, rgba(220,30,40,.55) 100%)" }} />
          <div className="absolute inset-x-0 top-16 flex justify-center">
            <div role="alert" className="glass anim-pop flex items-center gap-3 rounded-xl border border-pl-red/60 bg-pl-bg1 px-5 py-3 shadow-[0_0_48px_-8px_rgba(240,60,60,.7)]">
              <TriangleAlert size={20} className="text-pl-red" />
              <div><div className="text-sm font-semibold uppercase tracking-[0.18em] text-pl-red">{incident.title}</div>
                <div className="text-xs text-pl-text">{incident.text}</div></div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
