/**
 * Server-side search with debounce and pagination for selects/comboboxes.
 *
 * Pushes search events to LiveView and expects updated options via props.
 *
 * Usage:
 *   const { query, search, loadMore } = useServerSearch({
 *     searchEvent: "search_sheets",
 *     loadMoreEvent: "load_more_sheets",
 *     debounceMs: 300,
 *   })
 */

import { useDebounceFn } from "@vueuse/core";
import { type Ref, ref } from "vue";
import { useLive } from "./useLive";

export interface UseServerSearchOptions {
  searchEvent?: string;
  loadMoreEvent?: string;
  debounceMs?: number;
  /**
   * Extra fields merged into every pushed payload, on top of `{ query }`.
   *
   * A getter rather than a value so callers can feed it reactive state and
   * have it read at push time. Some server handlers need more than the query
   * to answer — `search_references` resolves a block's `allowed_types` from a
   * `block-id` — and without this they had to bypass `search()` entirely,
   * which silently disabled the debounce and the loading flag.
   */
  extraPayload?: () => Record<string, unknown>;
}

export interface UseServerSearchReturn {
  query: Ref<string>;
  loading: Ref<boolean>;
  search: (q: string) => void;
  loadMore: () => void;
  reset: () => void;
}

export function useServerSearch(options: UseServerSearchOptions = {}): UseServerSearchReturn {
  const {
    searchEvent = "search",
    loadMoreEvent = "load_more",
    debounceMs = 300,
    extraPayload,
  } = options;

  const live = useLive();
  const query = ref("");
  const loading = ref(false);

  const debouncedSearch = useDebounceFn((q: string) => {
    live.pushEvent(searchEvent, { query: q, ...extraPayload?.() }, () => {
      loading.value = false;
    });
  }, debounceMs);

  function search(q: string): void {
    query.value = q;
    loading.value = true;
    debouncedSearch(q);
  }

  function loadMore(): void {
    live.pushEvent(loadMoreEvent, { ...extraPayload?.() });
  }

  function reset(): void {
    query.value = "";
    loading.value = false;
  }

  return { query, loading, search, loadMore, reset };
}
