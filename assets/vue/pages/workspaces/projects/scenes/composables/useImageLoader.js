import { onUnmounted, ref, watch } from "vue";

/**
 * Reactive image loader. Given a computed map of { id → url }, loads images
 * and provides a reactive object of { [id]: HTMLImageElement }.
 *
 * @param {import('vue').Ref<Map<string|number, string|null>>} urlMapRef
 * @returns {{ images: import('vue').Ref<Object<string, HTMLImageElement>> }}
 */
export function useImageLoader(urlMapRef) {
	const images = ref({});
	const urlCache = new Map(); // url → HTMLImageElement
	const pendingUrls = new Map(); // id → url (currently loading)
	let aborted = false;

	function loadUrl(id, url) {
		// Already loaded for this URL
		if (urlCache.has(url)) {
			const cached = urlCache.get(url);
			if (cached) {
				images.value = { ...images.value, [id]: cached };
			}
			return;
		}

		// Already loading this id+url
		if (pendingUrls.get(id) === url) {
			return;
		}
		pendingUrls.set(id, url);

		const img = new Image();
		img.crossOrigin = "anonymous";
		img.onload = () => {
			if (aborted) {
				return;
			}
			pendingUrls.delete(id);
			urlCache.set(url, img);
			images.value = { ...images.value, [id]: img };
		};
		img.onerror = () => {
			pendingUrls.delete(id);
			urlCache.set(url, null);
		};
		img.src = url;
	}

	watch(
		urlMapRef,
		(urlMap) => {
			// Start loading any new entries
			for (const [id, url] of urlMap) {
				if (!url) {
					continue;
				}
				if (!images.value[id]) {
					loadUrl(id, url);
				}
			}

			// Remove entries no longer in the map
			const currentIds = new Set([...urlMap.keys()].map(String));
			const toRemove = Object.keys(images.value).filter(
				(id) => !currentIds.has(id),
			);
			if (toRemove.length > 0) {
				const next = { ...images.value };
				for (const id of toRemove) {
					delete next[id];
				}
				images.value = next;
			}
		},
		{ immediate: true },
	);

	onUnmounted(() => {
		aborted = true;
	});

	return { images };
}
