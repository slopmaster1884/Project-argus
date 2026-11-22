import { useEffect, useState } from "react";
import { animSrc, motionOff, useAppearance } from "../../lib/theme";
import { useT } from "../../lib/i18n";

/** Start-up intro: the theme's animated clip (green by default) under the ARGUS wordmark. ~2.4 s, click to skip. */
export default function Splash({ onDone, preview = false }: { onDone: () => void; preview?: boolean }) {
  const { theme, splash } = useAppearance();
  const t = useT();
  const [leaving, setLeaving] = useState(false);
  const skip = !preview && (!splash || motionOff());

  useEffect(() => {
    if (skip) { onDone(); return; }
    const a = setTimeout(() => setLeaving(true), 2200);
    const b = setTimeout(onDone, 2750);
    return () => { clearTimeout(a); clearTimeout(b); };
  }, [skip, onDone]);
  if (skip) return null;

  return (
    <div role="presentation" onClick={() => { setLeaving(true); setTimeout(onDone, 300); }}
      className="fixed inset-0 z-[100] flex cursor-pointer items-center justify-center overflow-hidden bg-black"
      style={leaving ? { animation: "argus-fade-out .5s ease forwards" } : undefined}>
      <video className="argus-anim absolute inset-0 h-full w-full object-cover opacity-90" src={animSrc(theme)} autoPlay muted loop playsInline
        onError={(e) => { (e.currentTarget as HTMLVideoElement).style.display = "none"; }} />
      <div className="absolute inset-0" style={{ background: "radial-gradient(ellipse at center, rgba(0,0,0,.15) 0%, rgba(0,0,0,.75) 75%)" }} />
      <div className="relative flex flex-col items-center gap-3 text-center">
        <div className="glass rounded-xl border border-white/15 bg-black/30 px-10 py-6 shadow-[0_0_60px_-10px_rgb(var(--accent-glow)/.7)]">
          <div className="text-4xl font-semibold text-white" style={{ animation: "argus-logo 1.1s cubic-bezier(.2,.8,.2,1) both", letterSpacing: ".32em" }}>ARGUS</div>
          <div className="mt-2 text-xs uppercase tracking-[0.3em] text-white/70">{t("splash.sub")}</div>
        </div>
        <div className="text-2xs text-white/40">{t("splash.skip")}</div>
      </div>
    </div>
  );
}
