import clsx from "clsx";
import { useCluster } from "../store/cluster";

export default function StatusBar() {
  const { snapshot, run } = useCluster();
  const rpc = snapshot?.rpcServers ?? [];
  const log = run.status === "loading" ? run.log : undefined;
  return (
    <footer className="flex h-7 min-w-0 items-center gap-4 overflow-hidden whitespace-nowrap border-t border-pl-line/70 bg-pl-bg2 px-4 font-mono text-2xs text-pl-dim">
      <span title={snapshot && !snapshot.adbOk ? "adb не отвечает — будет перезапущен автоматически" : "adb работает"}>
        <span className={clsx("mr-1 inline-block h-1.5 w-1.5 rounded-full align-middle", snapshot && !snapshot.adbOk ? "bg-pl-red" : "bg-pl-green shadow-[0_0_6px_rgb(var(--pl-green))]")} /> adb bridge</span>
      <span className="hidden md:inline" title={snapshot?.beaconError || "слушаем Wi-Fi маяки нод на UDP 50053"}>
        <span className={clsx("mr-1 inline-block h-1.5 w-1.5 rounded-full align-middle", snapshot?.beaconError ? "bg-pl-red" : "bg-pl-cyan shadow-[0_0_6px_rgb(var(--pl-cyan))]")} /> wi-fi discovery{snapshot?.discovered.length ? ` (${snapshot.discovered.length})` : ""}</span>
      <span className="min-w-0 shrink truncate" title={rpc.join(", ")}>rpc: {rpc.length ? rpc.join(", ") : "none"}</span>
      <span className="hidden 2xl:inline">engine: llama.cpp · 127.0.0.1:8080</span>
      {log && <span className="min-w-0 flex-1 truncate text-pl-mute" title={log}>› {log}</span>}
      <button className="ml-auto shrink-0 hover:text-pl-text" title="О программе · проверить обновления" onClick={() => useCluster.getState().setAbout(true)}>
        {snapshot?.platform ?? ""} · v{snapshot?.appVersion ?? "0.3.1"}
      </button>
    </footer>
  );
}
