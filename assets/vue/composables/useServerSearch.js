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
import { ref } from "vue";
import { useLive } from "./useLive";

export function useServerSearch(options = {}) {
	const {
		searchEvent = "search",
		loadMoreEvent = "load_more",
		debounceMs = 300,
	} = options;

	const live = useLive();
	const query = ref("");
	const loading = ref(false);

	const debouncedSearch = useDebounceFn((q) => {
		live.pushEvent(searchEvent, { query: q }, () => {
			loading.value = false;
		});
	}, debounceMs);

	function search(q) {
		query.value = q;
		loading.value = true;
		debouncedSearch(q);
	}

	function loadMore() {
		live.pushEvent(loadMoreEvent, {});
	}

	function reset() {
		query.value = "";
		loading.value = false;
	}

	return { query, loading, search, loadMore, reset };
}
