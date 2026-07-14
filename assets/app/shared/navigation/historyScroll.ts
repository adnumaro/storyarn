const PENDING_HISTORY_SCROLL_KEY = "storyarn:pending-history-scroll";
const HISTORY_SCROLL_KEY_PREFIX = "storyarn:history-scroll:";

interface HistoryStateWithScroll {
  id?: unknown;
  position?: unknown;
  scroll?: unknown;
}

function finiteScroll(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function historyEntryKey(state: HistoryStateWithScroll | null): string | null {
  const position = finiteScroll(state?.position);
  if (typeof state?.id !== "string" || position === null) return null;

  return `${HISTORY_SCROLL_KEY_PREFIX}${state.id}:${position}`;
}

function rememberedHistoryScroll(state: HistoryStateWithScroll | null): number | null {
  const key = historyEntryKey(state);
  if (!key) return null;

  const value = window.sessionStorage.getItem(key);
  return value === null ? null : finiteScroll(Number(value));
}

export function rememberCurrentHistoryScroll(): void {
  const state = (window.history.state || {}) as HistoryStateWithScroll;
  const scroll = window.scrollY;
  const key = historyEntryKey(state);

  // A click starts a new forward navigation, so any unconsumed popstate value
  // belongs to an older traversal and must not leak into the next page.
  window.sessionStorage.removeItem(PENDING_HISTORY_SCROLL_KEY);
  if (key) window.sessionStorage.setItem(key, String(scroll));
  window.history.replaceState({ ...state, scroll }, "", window.location.href);
}

export function capturePendingHistoryScroll(state: unknown): void {
  const historyState = state as HistoryStateWithScroll | null;
  const scroll = rememberedHistoryScroll(historyState) ?? finiteScroll(historyState?.scroll);

  if (scroll === null) {
    window.sessionStorage.removeItem(PENDING_HISTORY_SCROLL_KEY);
  } else {
    window.sessionStorage.setItem(PENDING_HISTORY_SCROLL_KEY, String(scroll));
  }
}

export function clearPendingHistoryScroll(): void {
  window.sessionStorage.removeItem(PENDING_HISTORY_SCROLL_KEY);
}

export function clearRememberedHistoryScroll(state: unknown): void {
  const key = historyEntryKey(state as HistoryStateWithScroll | null);
  if (key) window.sessionStorage.removeItem(key);
}

export function consumeHistoryScroll(fallback = 0): number {
  const pendingScroll = window.sessionStorage.getItem(PENDING_HISTORY_SCROLL_KEY);
  window.sessionStorage.removeItem(PENDING_HISTORY_SCROLL_KEY);

  if (pendingScroll !== null) {
    const parsedScroll = Number(pendingScroll);
    if (Number.isFinite(parsedScroll)) return parsedScroll;
  }

  return finiteScroll((window.history.state as HistoryStateWithScroll | null)?.scroll) ?? fallback;
}
