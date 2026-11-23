// Plain-language errors. Technical text (mostly Russian strings from Rust, plus llama.cpp / adb / OS messages)
// is matched on stable substrings and turned into a short title + what to do. The raw text is always kept so the UI
// can show it under «Подробнее». Rust messages are NOT changed — only recognised here.
import { t as tr, type I18nKey } from "./i18n";
import { useCluster } from "../store/cluster";

export type ErrorKind =
  | "pinRequired" | "pinBad" | "apk" | "protocol" | "busy" | "oom" | "disk" | "modelMissing" | "port"
  | "adbUnauthorized" | "adbMissing" | "adbOffline" | "rpcConnect" | "refused" | "timeout" | "download"
  | "engineDown" | "noModel" | "engine";

export interface HumanError {
  /** recognised kind, or null when the raw text is shown as is */
  kind: ErrorKind | null;
  title: string;
  hint: string;
  /** original text (without a leading "Error: ") */
  raw: string;
}

type T = (k: I18nKey) => string;

/** Order matters: the most specific patterns first («Движок не запустился: cudaMalloc … out of memory» is oom). */
const RULES: [ErrorKind, RegExp][] = [
  ["pinRequired", /PIN_REQUIRED|secured gateway|нужен PIN/i],
  ["pinBad", /неверный PIN|отклонила ключ|не подтвердила PIN|отказала в сопряжении|PIN — это 6 цифр/i],
  ["apk", /node\.apk не найден|apk.*not found/i],
  ["protocol", /протокол v\d|protocol (version )?mismatch|RPC_PROTO|ошибка протокола/i],
  ["busy", /занят другим клиентом|!busy:/i],
  ["oom", /out of memory|OutOfDeviceMemory|failed to allocate|unable to allocate|cudaMalloc|not enough memory|insufficient memory|не хватает памяти|недостаточно памяти|bad_alloc/i],
  ["disk", /no space left|os error 28\b|os error 112\b|недостаточно места|disk full/i],
  ["modelMissing", /failed to load model|unable to open|failed to open .*gguf|no such file|cannot find the file|os error 2\b|файл .* не найден|model file not found/i],
  ["port", /address already in use|addrinuse|couldn'?t bind|only one usage of each socket|os error 10048\b|os error 98\b|порт .*занят/i],
  ["adbUnauthorized", /unauthori[sz]ed/i],
  ["adbMissing", /не удалось запустить adb|adb(\.exe)?: (command )?not found|adb.*(не найден|cannot find)/i],
  ["adbOffline", /adb .*нет ответа|device offline|no devices|device '.*' not found|device not found/i],
  ["rpcConnect", /failed to connect to rpc|rpc.*(connect|connection).*fail|не удалось пробросить порт/i],
  ["refused", /connection refused|econnrefused|actively refused|os error 10061\b|os error 111\b|в подключении отказано/i],
  ["timeout", /timed? ?out|таймаут|нет ответа|os error 10060\b|os error 110\b/i],
  ["download", /hugging face (ответил|недоступен)|загрузка оборвалась|загрузка зависла|скачалось \d+ из|dns error|error sending request|не получилось скачать|не удалось скачать/i],
  ["engineDown", /failed to fetch|networkerror|load failed|нет связи с движком/i],
  ["noModel", /модель не запущена|нет модели для перезапуска/i],
  ["engine", /движок не запустился|движок остановился|engine process exited/i],
];

export function rawError(e: unknown): string {
  const s = e instanceof Error ? e.message : typeof e === "string" ? e : (() => { try { return JSON.stringify(e); } catch { return String(e); } })();
  return String(s ?? "").replace(/^(Error|TypeError):\s*/, "").trim();
}

export function classifyError(raw: string): ErrorKind | null {
  for (const [k, re] of RULES) if (re.test(raw)) return k;
  return null;
}

/** Turn any error into title + hint for a non-technical user; `t` = useT() inside React or the global t. */
export function humanizeError(e: unknown, t: T = (k) => tr(k)): HumanError {
  const raw = rawError(e);
  const kind = classifyError(raw);
  if (!kind) return { kind: null, title: raw || t("err.unknown.title"), hint: "", raw };
  return { kind, title: t(`err.${kind}.title` as I18nKey), hint: t(`err.${kind}.hint` as I18nKey), raw };
}

/** Error toast with the plain text on top and the raw text under «Подробнее». */
export function toastError(e: unknown, kind: "error" | "warn" = "error", prefix?: string) {
  const h = humanizeError(e);
  const raw = prefix ? `${prefix}: ${h.raw}` : h.raw;
  if (!h.kind) useCluster.getState().pushToast(kind, raw);
  else useCluster.getState().pushToast(kind, h.hint ? `${h.title}. ${h.hint}` : h.title, raw);
}
