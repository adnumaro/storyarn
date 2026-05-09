/**
 * Shared canvas tool state for the Flow editor.
 *
 * `activeFlowTool` drives whether dragging on empty canvas pans the viewport
 * (`"pan"`) or draws a marquee selection rectangle (`"select"`). Both
 * `FlowDock.vue` (writer, on button click) and `useFlowCanvas.ts` (reader,
 * watches the ref to attach / detach the marquee handler) import this.
 *
 * Client-only — no LiveView round-trip. Tool mode has no server side
 * effects.
 */

import { ref } from "vue";

export type FlowTool = "select" | "pan";

/** Default `"pan"` keeps the pre-dock behavior for anyone who hasn't clicked. */
export const activeFlowTool = ref<FlowTool>("pan");
