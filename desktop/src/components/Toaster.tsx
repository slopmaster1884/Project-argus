import { CheckCircle2, Info, TriangleAlert, X, XCircle } from "lucide-react";
import clsx from "clsx";
import { useCluster } from "../store/cluster";
import { Details } from "./ErrorBox";

const ICON = { info: Info, ok: CheckCircle2, warn: TriangleAlert, error: XCircle };
const TONE = {
  info: "border-pl-blue/60 text-pl-blue",
  ok: "border-pl-green/60 text-pl-green",
  warn: "border-pl-orange/60 text-pl-orange",
  error: "border-pl-red/60 text-pl-red",
};

/** Bottom-right notifications (cluster changes, engine restarts, adb restarts, found Wi-Fi nodes). */
export default function Toaster() {
  const { toasts, dismissToast, keepToast } = useCluster();
  if (!toasts.length) return null;
  return (
    <div className="pointer-events-none fixed bottom-8 right-4 z-[60] flex w-[380px] max-w-[calc(100vw-2rem)] flex-col gap-2">
      {toasts.map((t) => {
        const I = ICON[t.kind];
        return (
          <div key={t.id} className={clsx("glass anim-pop pointer-events-auto flex items-start gap-2 rounded-md border-l-2 border-y border-r border-y-pl-line2/60 border-r-pl-line2/60 bg-pl-bg2 px-3 py-2 text-xs shadow-2xl", TONE[t.kind])}>
            <I size={14} className="mt-0.5 shrink-0" />
            <div className="min-w-0 flex-1"><div className="leading-5 text-pl-text">{t.text}</div>
              {t.detail && <Details raw={t.detail} className="mt-0.5" onOpen={() => keepToast(t.id)} />}</div>
            <button className="text-pl-dim hover:text-pl-text" onClick={() => dismissToast(t.id)}><X size={12} /></button>
          </div>
        );
      })}
    </div>
  );
}
