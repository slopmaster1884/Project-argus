import { useCluster } from "../store/cluster";
import { NODE_COLORS } from "./MemoryPool";
import { gb } from "../lib/format";
import type { ClusterNode } from "../lib/types";

/** Gotham-style link graph: host in the centre, USB nodes on an arc. */
export default function Topology({ selected, onSelect }: { selected: string; onSelect: (id: string) => void }) {
  const snap = useCluster((s) => s.snapshot);
  if (!snap) return null;
  const W = 560, H = 300, cx = W / 2, cy = H / 2 + 10;
  const nodes = snap.nodes;
  const n = nodes.length;
  // ring around the host; avoid straight up/down for 2 nodes and the host label below
  const angle = (i: number) => n === 1 ? 0 : n === 2 ? (i === 0 ? Math.PI : 0)
    : -Math.PI / 2 + (2 * Math.PI * i) / n + (n % 2 === 0 ? Math.PI / n : 0);
  const pos = nodes.map((_, i) => ({ x: cx + Math.cos(angle(i)) * 200, y: cy - 10 + Math.sin(angle(i)) * 95 }));

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-full w-full">
      <defs>
        <pattern id="g" width="16" height="16" patternUnits="userSpaceOnUse"><circle cx="1" cy="1" r=".8" fill="rgb(var(--pl-line))" opacity=".6" /></pattern>
        <radialGradient id="halo"><stop offset="0%" stopColor="rgb(var(--accent-glow))" stopOpacity=".28" /><stop offset="100%" stopColor="rgb(var(--accent-glow))" stopOpacity="0" /></radialGradient>
        <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3" result="b" /><feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
      </defs>
      <rect width={W} height={H} fill="url(#g)" />
      <ellipse cx={cx} cy={cy} rx="150" ry="90" fill="url(#halo)" />
      {nodes.map((n, i) => {
        const on = n.stage === "connected";
        return (
          <g key={`l-${n.id}`}>
            <line x1={cx} y1={cy} x2={pos[i].x} y2={pos[i].y} stroke={!n.enabled ? "rgb(var(--pl-line2))" : on ? (n.transport === "lan" ? "rgb(var(--pl-cyan))" : "rgb(var(--pl-blue))") : "rgb(var(--pl-orange))"} strokeWidth={on ? 1.6 : 1.2} strokeLinecap="round"
              strokeDasharray={on && n.transport !== "lan" ? "0" : n.transport === "lan" && on ? "6 3" : "4 4"} opacity={0.75} filter={on ? "url(#glow)" : undefined} />
            {on && <circle r="3" fill="rgb(var(--pl-blue))" filter="url(#glow)">
              <animateMotion dur="1.8s" repeatCount="indefinite" path={`M${cx},${cy} L${pos[i].x},${pos[i].y}`} />
            </circle>}
            <text x={(cx + pos[i].x) / 2} y={(cy + pos[i].y) / 2 - 6} textAnchor="middle" className="fill-pl-dim font-mono" fontSize="9">
              {n.transport === "lan" ? `LAN · ${n.endpoint}` : n.link === "tether" && on ? `USB-модем · ${n.endpoint}` : n.endpoint ?? n.stage.toUpperCase()}
            </text>
          </g>
        );
      })}
      <Glyph node={snap.host} x={cx} y={cy} color={NODE_COLORS[0]} big sel={selected === snap.host.id} onClick={() => onSelect(snap.host.id)}
        sub={snap.gpus.length > 1 ? snap.gpus.map((g) => `${g.device}${g.enabled ? "" : " off"}`).join(" · ") : undefined} />
      {nodes.map((n, i) => (
        <Glyph key={n.id} node={n} x={pos[i].x} y={pos[i].y} color={NODE_COLORS[(i + 1) % 6]} sel={selected === n.id} onClick={() => onSelect(n.id)} />
      ))}
      {nodes.length === 0 && (
        <text x={cx} y={cy + 60} textAnchor="middle" className="fill-pl-dim font-mono" fontSize="10">NO NODES · PLUG IN A DEVICE OR ADD ONE BY IP</text>
      )}
    </svg>
  );
}

function Glyph({ node, x, y, color, big, sel, onClick, sub }: {
  node: ClusterNode; x: number; y: number; color: string; big?: boolean; sel: boolean; onClick: () => void; sub?: string;
}) {
  const s = big ? 30 : 22;
  const on = node.stage === "connected" && node.enabled;
  return (
    <g transform={`translate(${x},${y})`} onClick={onClick} className="cursor-pointer">
      {sel && <rect x={-s - 6} y={-s - 6} width={(s + 6) * 2} height={(s + 6) * 2} rx="12" fill="none" stroke="rgb(var(--pl-blue))" strokeWidth="1.5" strokeDasharray="4 3">
        <animate attributeName="stroke-dashoffset" from="0" to="14" dur="1.2s" repeatCount="indefinite" /></rect>}
      <rect x={-s} y={-s} width={s * 2} height={s * 2} rx="9" fill="rgb(var(--pl-bg2))" stroke={on ? color : "rgb(var(--pl-orange))"} strokeWidth={1.6} filter={on ? "url(#glow)" : undefined} />
      <rect x={-s + 6} y={-s} width={s * 2 - 12} height={2.5} rx="1.2" fill={on ? color : "rgb(var(--pl-orange))"} />
      <text y={big ? -2 : 0} textAnchor="middle" className="fill-pl-text font-mono" fontSize={big ? 11 : 9}>{node.kind.toUpperCase()}</text>
      <text y={big ? 12 : 11} textAnchor="middle" className="fill-pl-mute font-mono" fontSize="9">{gb(node.totalMb)}G</text>
      <text y={s + 15} textAnchor="middle" className="fill-pl-text" fontSize="10.5" fontWeight="600">{node.name}</text>
      {sub && <text y={s + 26} textAnchor="middle" className="fill-pl-dim font-mono" fontSize="8">{sub}</text>}
      {node.transport === "lan" && <g transform={`translate(${s - 12},${-s - 7})`}><rect width="22" height="11" rx="5.5" fill="rgb(var(--pl-bg0))" stroke="rgb(var(--pl-cyan))" /><text x="11" y="8.5" textAnchor="middle" fontSize="7.5" className="font-mono" fill="rgb(var(--pl-cyan))">LAN</text></g>}
    </g>
  );
}
