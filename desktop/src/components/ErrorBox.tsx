import { useState } from "react";
import { ChevronDown, ChevronRight } from "lucide-react";
import clsx from "clsx";
import { useT } from "../lib/i18n";
import { humanizeError } from "../lib/errors";

/** Raw technical text behind a «Подробнее / Details» toggle. */
export function Details({ raw, className, onOpen }: { raw: string; className?: string; onOpen?: () => void }) {
  const t = useT();
  const [open, setOpen] = useState(false);
  if (!raw) return null;
  return (
    <div className={className}>
      <button type="button" className="flex items-center gap-1 text-2xs text-pl-dim hover:text-pl-text"
        onClick={() => { setOpen(!open); if (!open) onOpen?.(); }}>
        {open ? <ChevronDown size={11} /> : <ChevronRight size={11} />} {open ? t("err.hide") : t("err.details")}
      </button>
      {open && <pre className="mt-1 max-h-40 select-text overflow-auto whitespace-pre-wrap break-words border border-pl-line bg-pl-bg0 p-2 font-mono text-2xs text-pl-mute">{raw}</pre>}
    </div>
  );
}

/**
 * Plain-language error: what happened + what to do, raw text under «Подробнее».
 * Unrecognised errors are shown as they are (Rust messages are mostly human Russian already).
 */
export default function ErrorBox({ error, className, tone = "red" }: { error: unknown; className?: string; tone?: "red" | "orange" }) {
  const t = useT();
  const h = humanizeError(error, t);
  const c = tone === "red" ? "border-pl-red bg-pl-red/10 text-pl-red" : "border-pl-orange bg-pl-orange/10 text-pl-orange";
  return (
    <div className={clsx("border-l-2 p-2 text-xs leading-5", c, className)}>
      <div className="font-medium">{h.title}</div>
      {h.hint && <div className="text-pl-text">{h.hint}</div>}
      {h.kind && <Details raw={h.raw} className="mt-1" />}
    </div>
  );
}
