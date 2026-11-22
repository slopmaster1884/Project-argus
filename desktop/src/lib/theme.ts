// Argus v2 appearance: theme (from the user's design pack), glass level, background, animations.
// Stored in localStorage (instant first paint, no Rust round-trip). Applied as data-* attributes on <html>;
// the colours themselves live in src/theme.css.
import { create } from "zustand";

export type ThemeId = "green" | "pink" | "black" | "mono";
export type Glass = "off" | "low" | "mid" | "high";
export type Bg = "image" | "drift" | "plain" | "window";
export type Motion = "auto" | "full" | "off";

export interface Appearance {
  theme: ThemeId;
  glass: Glass;
  bg: Bg;
  motion: Motion;       // auto = follow the OS «reduce motion»
  splash: boolean;      // animated intro on start
  fxNotify: boolean;    // little animation with notifications
  fxIncident: boolean;  // full-screen flash on incidents (node lost, overheating, engine error)
}

export const THEMES: { id: ThemeId; swatch: [string, string]; light: boolean }[] = [
  { id: "green", swatch: ["#0e1e17", "#3ddc84"], light: false },
  { id: "pink", swatch: ["#fbe8e9", "#c21848"], light: true },
  { id: "black", swatch: ["#0c0c0e", "#d6d6de"], light: false },
  { id: "mono", swatch: ["#f6f6f4", "#141416"], light: true },
];

/** Animated clip for a theme (black / mono reuse the green clip through a CSS filter, see --anim-filter). */
export const animSrc = (t: ThemeId) => `/theme/anim-${t === "pink" ? "pink" : "green"}.webm`;

const DEFAULTS: Appearance = { theme: "green", glass: "mid", bg: "image", motion: "auto", splash: true, fxNotify: true, fxIncident: true };
const KEY = "argus.appearance";

function load(): Appearance {
  try {
    const raw = typeof localStorage !== "undefined" ? localStorage.getItem(KEY) : null;
    if (raw) return { ...DEFAULTS, ...JSON.parse(raw) };
  } catch { /* ignore */ }
  return DEFAULTS;
}

export function applyAppearance(a: Appearance) {
  if (typeof document === "undefined") return;
  const h = document.documentElement;
  h.dataset.theme = a.theme;
  h.dataset.glass = a.glass;
  h.dataset.bg = a.bg;
  h.dataset.motion = a.motion;
}

/** true when animations should not play (user switched them off, or the OS asks for reduced motion in «auto»). */
export function motionOff(a: Appearance = useAppearance.getState()): boolean {
  if (a.motion === "off") return true;
  if (a.motion === "full") return false;
  return typeof window !== "undefined" && !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
}

export const useAppearance = create<Appearance & { set: (p: Partial<Appearance>) => void; reset: () => void }>((set, get) => ({
  ...load(),
  set: (p) => {
    set(p);
    const { set: _s, reset: _r, ...a } = get();
    try { localStorage.setItem(KEY, JSON.stringify(a)); } catch { /* ignore */ }
    applyAppearance(a);
  },
  reset: () => get().set(DEFAULTS),
}));

applyAppearance(useAppearance.getState());

// Window transparency (Windows 11 mica / Windows 10 acrylic) only matters in bg = "window";
// tauri.windows.conf.json makes the window transparent, the CSS draws nothing behind the glass then.

/** UI state that is not persisted: the Appearance dialog and the splash replay. */
export const useAppearanceUi = create<{ open: boolean; splash: number; setOpen: (o: boolean) => void; replaySplash: () => void }>((set) => ({
  open: false,
  splash: 1,
  setOpen: (open) => set({ open }),
  replaySplash: () => set((s) => ({ splash: s.splash + 1, open: false })),
}));
