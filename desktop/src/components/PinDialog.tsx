import { useState } from "react";
import { KeyRound, Loader2, X } from "lucide-react";
import { useT } from "../lib/i18n";

/** PIN prompt for adding a secured node (beacon `auth`, rpcauth.rs). `onSubmit` throws → the error is shown. */
export default function PinDialog({ name, onSubmit, onClose }: { name: string; onSubmit: (pin: string) => Promise<void>; onClose: () => void }) {
  const t = useT();
  const [pin, setPin] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const digits = pin.replace(/\D/g, "");
  async function submit() {
    if (digits.length !== 6 || busy) return;
    setBusy(true); setErr(null);
    try { await onSubmit(digits); onClose(); } catch (e) { setErr(String(e).replace(/^Error:\s*/, "")); }
    setBusy(false);
  }
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
      <div className="w-[420px] max-w-[calc(100vw-2rem)] border border-pl-line2 bg-pl-bg1 shadow-2xl">
        <div className="flex h-9 items-center justify-between border-b border-pl-line bg-pl-bg2 px-3">
          <span className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.12em] text-pl-mute"><KeyRound size={13} /> {t("sec.pinTitle")}</span>
          <button onClick={onClose} className="text-pl-dim hover:text-pl-text"><X size={15} /></button>
        </div>
        <div className="space-y-3 p-4 text-xs leading-5 text-pl-mute">
          <p>{t("sec.pinDesc").replace("{name}", name)}</p>
          <label className="block"><span className="label">{t("sec.pinLabel")}</span>
            <input autoFocus inputMode="numeric" value={pin} maxLength={7} placeholder="123 456"
              onChange={(e) => setPin(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") submit(); }}
              className="mt-1 h-10 w-full border border-pl-line2 bg-pl-bg0 px-2 text-center font-mono text-xl tracking-[0.3em] text-pl-text outline-none focus:border-pl-blue" />
          </label>
          {err && <div className="border-l-2 border-pl-red bg-pl-red/10 p-2 font-mono text-2xs text-pl-red">{err}</div>}
        </div>
        <div className="flex justify-end gap-2 border-t border-pl-line bg-pl-bg2 px-3 py-2">
          <button className="btn" onClick={onClose}>{t("sec.cancel")}</button>
          <button className="btn-primary" disabled={digits.length !== 6 || busy} onClick={submit}>{busy && <Loader2 size={12} className="animate-spin" />} {t("sec.pair")}</button>
        </div>
      </div>
    </div>
  );
}
