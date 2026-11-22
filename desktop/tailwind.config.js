/** @type {import('tailwindcss').Config} */
// v2 «Argus Serpent» design: themes from the user's design pack (green default, pink, black, black & white).
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // v2: every colour is a CSS variable set by the active theme (src/theme.css).
        // Surfaces (bg0..bg4) also carry the theme's glass alpha, so panels go translucent everywhere.
        pl: {
          bg0: "rgb(var(--pl-bg0) / calc(var(--glass-bg0, 1) * <alpha-value>))",
          bg1: "rgb(var(--pl-bg1) / calc(var(--glass-bg1, 1) * <alpha-value>))",
          bg2: "rgb(var(--pl-bg2) / calc(var(--glass-bg2, 1) * <alpha-value>))",
          bg3: "rgb(var(--pl-bg3) / calc(var(--glass-bg3, 1) * <alpha-value>))",
          bg4: "rgb(var(--pl-bg4) / calc(var(--glass-bg4, 1) * <alpha-value>))",
          line: "rgb(var(--pl-line) / <alpha-value>)",
          line2: "rgb(var(--pl-line2) / <alpha-value>)",
          text: "rgb(var(--pl-text) / <alpha-value>)",
          mute: "rgb(var(--pl-mute) / <alpha-value>)",
          dim: "rgb(var(--pl-dim) / <alpha-value>)",
          blue: "rgb(var(--pl-blue) / <alpha-value>)",
          blue2: "rgb(var(--pl-blue2) / <alpha-value>)",
          green: "rgb(var(--pl-green) / <alpha-value>)",
          orange: "rgb(var(--pl-orange) / <alpha-value>)",
          red: "rgb(var(--pl-red) / <alpha-value>)",
          gold: "rgb(var(--pl-gold) / <alpha-value>)",
          cyan: "rgb(var(--pl-cyan) / <alpha-value>)",
          violet: "rgb(var(--pl-violet) / <alpha-value>)",
          rose: "rgb(var(--pl-rose) / <alpha-value>)",
        },
      },
      fontFamily: {
        sans: ["Inter Variable", "Inter", "-apple-system", "Segoe UI", "system-ui", "sans-serif"],
        mono: ["JetBrains Mono Variable", "JetBrains Mono", "SFMono-Regular", "Consolas", "ui-monospace", "monospace"],
      },
      borderRadius: { DEFAULT: "6px", sm: "4px", md: "8px", lg: "12px", xl: "16px" },
      fontSize: { "2xs": ["10px", "14px"] },
      keyframes: { blink: { "0%,100%": { opacity: "1" }, "50%": { opacity: ".35" } },
                   sweep: { "0%": { transform: "translateX(-100%)" }, "100%": { transform: "translateX(300%)" } } },
      animation: { blink: "blink 1.4s ease-in-out infinite", sweep: "sweep 1.6s linear infinite" },
      backdropBlur: { glass: "var(--glass-blur)" },
    },
  },
  plugins: [],
};
