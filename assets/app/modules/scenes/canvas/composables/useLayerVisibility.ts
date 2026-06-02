import { computed, type Ref, type ComputedRef } from "vue";

export interface LayerData {
  id: number | string;
  visible: boolean;
  fogEnabled?: boolean;
}

/**
 * Shared computed for filtering hidden layer IDs.
 * Used by usePins, useZones, useAnnotations, and useConnections.
 */
export function useHiddenLayerIds(
  layers: Ref<LayerData[]> | ComputedRef<LayerData[]>,
): ComputedRef<Set<number | string>> {
  return computed(() => {
    const set = new Set<number | string>();
    for (const layer of layers.value) {
      if (!layer.visible) {
        set.add(layer.id);
      }
    }
    return set;
  });
}
