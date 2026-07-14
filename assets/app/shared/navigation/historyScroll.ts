const PENDING_HISTORY_SCROLL_KEY = "storyarn:pending-history-scroll";
const HISTORY_SCROLL_KEY_PREFIX = "storyarn:history-scroll:";
const MAX_REMEMBERED_HISTORY_SCROLLS = 50;

export type HistoryScrollTarget = "window" | "docs-main";

interface HistoryScrollPosition {
  target: HistoryScrollTarget;
  top: number;
}

interface HistoryStateWithScroll {
  id?: unknown;
  position?: unknown;
  scroll?: unknown;
  storyarnScroll?: unknown;
}

function finiteScroll(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function scrollPosition(value: unknown): HistoryScrollPosition | null {
  if (!value || typeof value !== "object") return null;

  const { target, top } = value as Partial<HistoryScrollPosition>;
  const finiteTop = finiteScroll(top);
  if ((target !== "window" && target !== "docs-main") || finiteTop === null) return null;

  return { target, top: finiteTop };
}

function historyEntryKey(state: HistoryStateWithScroll | null): string | null {
  const position = finiteScroll(state?.position);
  if (typeof state?.id !== "string" || position === null) return null;

  return `${HISTORY_SCROLL_KEY_PREFIX}${state.id}:${position}`;
}

function storageGet(key: string): string | null {
  try {
    return window.sessionStorage.getItem(key);
  } catch {
    return null;
  }
}

function storageRemove(key: string): void {
  try {
    window.sessionStorage.removeItem(key);
  } catch {
    // Scroll restoration is best effort and must never interrupt navigation.
  }
}

function rememberedStorageKeys(): string[] {
  const keys: string[] = [];

  try {
    for (let index = 0; index < window.sessionStorage.length; index += 1) {
      const key = window.sessionStorage.key(index);
      if (key?.startsWith(HISTORY_SCROLL_KEY_PREFIX)) keys.push(key);
    }
  } catch {
    return [];
  }

  return keys;
}

function pruneRememberedHistoryScrolls(currentKey: string): void {
  const staleKeys = rememberedStorageKeys().filter((key) => key !== currentKey);
  const excess = Math.max(0, staleKeys.length - MAX_REMEMBERED_HISTORY_SCROLLS + 1);

  for (const key of staleKeys.slice(0, excess)) storageRemove(key);
}

function storageSet(key: string, value: string): void {
  try {
    window.sessionStorage.setItem(key, value);
  } catch {
    // A long-lived tab can exhaust its quota. Drop only our bounded history
    // cache and retry once so other session data remains untouched.
    for (const rememberedKey of rememberedStorageKeys()) storageRemove(rememberedKey);

    try {
      window.sessionStorage.setItem(key, value);
    } catch {
      // Native history state remains as the fallback when storage is unavailable.
    }
  }
}

function parseStoredPosition(value: string | null): HistoryScrollPosition | null {
  if (value === null) return null;

  try {
    const parsed = JSON.parse(value);
    const legacyScroll = finiteScroll(parsed);

    return (
      scrollPosition(parsed) ??
      (legacyScroll === null ? null : { target: "window", top: legacyScroll })
    );
  } catch {
    const legacyScroll = finiteScroll(Number(value));
    return legacyScroll === null ? null : { target: "window", top: legacyScroll };
  }
}

function rememberedHistoryScroll(
  state: HistoryStateWithScroll | null,
): HistoryScrollPosition | null {
  const key = historyEntryKey(state);
  return key ? parseStoredPosition(storageGet(key)) : null;
}

function stateHistoryScroll(state: HistoryStateWithScroll | null): HistoryScrollPosition | null {
  const explicitPosition = scrollPosition(state?.storyarnScroll);
  if (explicitPosition) return explicitPosition;

  const windowScroll = finiteScroll(state?.scroll);
  return windowScroll === null ? null : { target: "window", top: windowScroll };
}

function currentScrollPosition(): HistoryScrollPosition {
  const docsMain = document.getElementById("docs-main");
  if (docsMain instanceof HTMLElement) return { target: "docs-main", top: docsMain.scrollTop };

  return { target: "window", top: window.scrollY };
}

export function rememberCurrentHistoryScroll(): void {
  const state = (window.history.state || {}) as HistoryStateWithScroll;
  const position = currentScrollPosition();
  const key = historyEntryKey(state);

  // A click starts a new forward navigation, so any unconsumed popstate value
  // belongs to an older traversal and must not leak into the next page.
  storageRemove(PENDING_HISTORY_SCROLL_KEY);

  if (key) {
    pruneRememberedHistoryScrolls(key);
    storageSet(key, JSON.stringify(position));
  }

  const nextState = { ...state, storyarnScroll: position };
  if (position.target === "window") nextState.scroll = position.top;
  window.history.replaceState(nextState, "", window.location.href);
}

export function capturePendingHistoryScroll(state: unknown): void {
  const historyState = state as HistoryStateWithScroll | null;
  const key = historyEntryKey(historyState);
  const position = rememberedHistoryScroll(historyState) ?? stateHistoryScroll(historyState);

  if (key) storageRemove(key);

  if (position === null) {
    storageRemove(PENDING_HISTORY_SCROLL_KEY);
  } else {
    storageSet(PENDING_HISTORY_SCROLL_KEY, JSON.stringify(position));
  }
}

export function clearPendingHistoryScroll(): void {
  storageRemove(PENDING_HISTORY_SCROLL_KEY);
}

export function clearRememberedHistoryScroll(state: unknown): void {
  const key = historyEntryKey(state as HistoryStateWithScroll | null);
  if (key) storageRemove(key);
}

export function consumeHistoryScroll(fallback = 0, target: HistoryScrollTarget = "window"): number {
  const pendingPosition = parseStoredPosition(storageGet(PENDING_HISTORY_SCROLL_KEY));
  storageRemove(PENDING_HISTORY_SCROLL_KEY);

  if (pendingPosition?.target === target) return pendingPosition.top;

  const statePosition = stateHistoryScroll(window.history.state as HistoryStateWithScroll | null);
  return statePosition?.target === target ? statePosition.top : fallback;
}
