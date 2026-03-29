import { computed } from "vue";

/**
 * Shared computed for filtering hidden layer IDs.
 * Used by usePins, useZones, useAnnotations, and useConnections.
 *
 * @param {import('vue').Ref<Array>} layers
 * @returns {import('vue').ComputedRef<Set<number|string>>}
 */
export function useHiddenLayerIds(layers) {
	return computed(() => {
		const set = new Set();
		for (const layer of layers.value) {
			if (!layer.visible) {
				set.add(layer.id);
			}
		}
		return set;
	});
}
