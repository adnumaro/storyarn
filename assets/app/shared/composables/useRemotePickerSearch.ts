import { computed, onUnmounted, ref, toValue, watch, type Ref } from "vue";
import { useLive } from "./useLive";

export interface RemotePickerSearchOptions {
  enabled: Ref<boolean> | boolean;
  event: Ref<string | undefined> | string | undefined;
  resultsEvent?: Ref<string | undefined> | string | undefined;
  payload?: Ref<Record<string, unknown> | undefined> | Record<string, unknown> | undefined;
  selectedId?: Ref<number | string | null | undefined> | number | string | null | undefined;
  limit: number;
  debounceMs?: number;
  responseTimeoutMs?: number;
}

export interface RemotePickerResults {
  request_id?: unknown;
  results?: unknown;
  items?: unknown;
  has_more?: unknown;
  hasMore?: unknown;
}

const DEFAULT_RESULTS_EVENT = "picker_search_results";
const DEFAULT_DEBOUNCE_MS = 160;
const DEFAULT_RESPONSE_TIMEOUT_MS = 10_000;

function randomRequestId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }

  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

export function useRemotePickerSearch<T>(options: RemotePickerSearchOptions) {
  const live = useLive();
  const query = ref("");
  const results = ref<T[]>([]) as Ref<T[]>;
  const hasMore = ref(false);
  const isSearching = ref(false);
  const hasResponse = ref(false);

  const isEnabled = computed(() => !!toValue(options.enabled) && !!toValue(options.event));
  const eventName = computed(() => toValue(options.event));
  const resultsEventName = computed(() => toValue(options.resultsEvent) || DEFAULT_RESULTS_EVENT);

  let debounceTimer: ReturnType<typeof setTimeout> | null = null;
  let responseTimer: ReturnType<typeof setTimeout> | null = null;
  let latestRequestId: string | null = null;
  let handlerRef: number | undefined;

  function clearTimer(): void {
    if (!debounceTimer) return;
    clearTimeout(debounceTimer);
    debounceTimer = null;
  }

  function clearResponseTimer(): void {
    if (!responseTimer) return;
    clearTimeout(responseTimer);
    responseTimer = null;
  }

  function finishSearch(requestId: string): void {
    if (latestRequestId !== requestId) return;

    clearResponseTimer();
    isSearching.value = false;
  }

  function searchNow(): void {
    clearTimer();

    const event = eventName.value;
    if (!isEnabled.value || !event) return;

    const requestId = randomRequestId();
    clearResponseTimer();
    latestRequestId = requestId;
    hasResponse.value = false;
    isSearching.value = true;

    responseTimer = setTimeout(
      () => finishSearch(requestId),
      options.responseTimeoutMs ?? DEFAULT_RESPONSE_TIMEOUT_MS,
    );

    live.pushEvent(
      event,
      {
        ...toValue(options.payload),
        request_id: requestId,
        query: query.value,
        limit: options.limit,
        selected_id: toValue(options.selectedId) ?? null,
      },
      undefined,
      () => finishSearch(requestId),
    );
  }

  function scheduleSearch(): void {
    if (!isEnabled.value) return;

    registerHandler();
    clearTimer();
    debounceTimer = setTimeout(searchNow, options.debounceMs ?? DEFAULT_DEBOUNCE_MS);
  }

  function registerHandler(): void {
    if (handlerRef !== undefined) return;

    handlerRef = live.handleEvent(resultsEventName.value, (payload: Record<string, unknown>) => {
      const response = payload as RemotePickerResults;
      const requestId = latestRequestId;
      if (!requestId || response.request_id !== requestId) return;

      const remoteResults = response.results ?? response.items;
      results.value = Array.isArray(remoteResults) ? (remoteResults as T[]) : [];
      hasMore.value = !!(response.has_more ?? response.hasMore);
      hasResponse.value = true;
      finishSearch(requestId);
    });
  }

  watch(
    () =>
      [
        query.value,
        isEnabled.value,
        eventName.value,
        toValue(options.payload),
        toValue(options.selectedId),
      ] as const,
    scheduleSearch,
    { immediate: true },
  );

  onUnmounted(() => {
    latestRequestId = null;
    clearTimer();
    clearResponseTimer();

    if (handlerRef !== undefined) {
      live.removeHandleEvent(handlerRef);
      handlerRef = undefined;
    }
  });

  return {
    query,
    results,
    hasMore,
    isSearching,
    hasResponse,
    refresh: searchNow,
  };
}
