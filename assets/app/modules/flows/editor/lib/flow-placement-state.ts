import { ref } from "vue";

import type { FlowNodeType } from "./node-configs";

export type FlowPlacementTarget = { kind: "node"; type: FlowNodeType } | { kind: "annotation" };

export const activeFlowPlacement = ref<FlowPlacementTarget | null>(null);

export function startFlowPlacement(target: FlowPlacementTarget): void {
  activeFlowPlacement.value = target;
}

export function cancelFlowPlacement(): void {
  activeFlowPlacement.value = null;
}
