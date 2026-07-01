import { computed, onUnmounted, ref, toValue, watch, type Ref } from "vue";

export interface BoundedSearchOptions<T> {
  items: Ref<T[]> | T[];
  limit: number;
  getText: (item: T) => string;
  getKey?: (item: T) => string;
  selectedKey?: Ref<string | null> | string | null;
  chunkSize?: number;
}

interface SearchEntry<T> {
  item: T;
  key: string | null;
  text: string;
}

const DEFAULT_CHUNK_SIZE = 500;
const COMBINING_MARKS_RE = /[\u0300-\u036f]/g;

export function normalizeSearchText(value: string): string {
  return value.normalize("NFD").replace(COMBINING_MARKS_RE, "").toLocaleLowerCase();
}

export function useBoundedSearch<T>(options: BoundedSearchOptions<T>) {
  const query = ref("");
  const visibleItems = ref<T[]>([]) as Ref<T[]>;
  const isSearching = ref(false);
  const isLimited = ref(false);

  let searchRunId = 0;
  let pendingTimer: ReturnType<typeof setTimeout> | null = null;

  const entries = computed<SearchEntry<T>[]>(() =>
    toValue(options.items).map((item) => ({
      item,
      key: options.getKey?.(item) ?? null,
      text: normalizeSearchText(options.getText(item)),
    })),
  );

  const selectedEntry = computed(() => {
    const selectedKey = toValue(options.selectedKey);
    if (selectedKey == null) return null;
    return entries.value.find((entry) => entry.key === selectedKey) ?? null;
  });

  function clearPendingTimer(): void {
    if (pendingTimer) {
      clearTimeout(pendingTimer);
      pendingTimer = null;
    }
  }

  function withSelectedItem(items: T[], normalizedQuery: string): T[] {
    const entry = selectedEntry.value;
    if (!entry) return items;
    if (normalizedQuery && !entry.text.includes(normalizedQuery)) return items;
    if (items.some((item) => item === entry.item)) return items;
    return [...items, entry.item];
  }

  function publish(items: T[], normalizedQuery: string, limited: boolean): void {
    visibleItems.value = withSelectedItem(items, normalizedQuery);
    isLimited.value = limited;
  }

  function search(): void {
    clearPendingTimer();

    const runId = ++searchRunId;
    const normalizedQuery = normalizeSearchText(query.value.trim());
    const maxResults = Math.max(0, options.limit);
    const indexed = entries.value;

    if (maxResults === 0) {
      visibleItems.value = [];
      isSearching.value = false;
      isLimited.value = indexed.length > 0;
      return;
    }

    if (!normalizedQuery) {
      publish(
        indexed.slice(0, maxResults).map((entry) => entry.item),
        normalizedQuery,
        indexed.length > maxResults,
      );
      isSearching.value = false;
      return;
    }

    const found: T[] = [];
    const chunkSize = options.chunkSize ?? DEFAULT_CHUNK_SIZE;
    let index = 0;

    isSearching.value = true;
    isLimited.value = false;
    visibleItems.value = [];

    const scanChunk = () => {
      if (runId !== searchRunId) return;

      const end = Math.min(index + chunkSize, indexed.length);

      while (index < end) {
        const entry = indexed[index];
        index += 1;

        if (!entry.text.includes(normalizedQuery)) continue;

        if (found.length >= maxResults) {
          publish(found, normalizedQuery, true);
          isSearching.value = false;
          return;
        }

        found.push(entry.item);
      }

      publish(found, normalizedQuery, false);

      if (index >= indexed.length) {
        isSearching.value = false;
        return;
      }

      pendingTimer = setTimeout(scanChunk, 0);
    };

    scanChunk();
  }

  watch([entries, query, selectedEntry], search, { immediate: true });

  onUnmounted(() => {
    searchRunId += 1;
    clearPendingTimer();
  });

  return {
    query,
    visibleItems,
    isSearching,
    isLimited,
  };
}
