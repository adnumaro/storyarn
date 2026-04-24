<script setup lang="ts">
/**
 * Minimal rendered representation of a Sequence on the canvas.
 *
 * Post-Phase 1 of the flow relational refactor, sequences are `FlowNode`
 * instances with `nodeType === 'sequence'`. The rete-scopes-plugin
 * auto-resizes this parent node based on its children; width/height
 * props are used as the initial/minimum size. Name lives in `nodeData.name`
 * (promoted from the 1:1 `flow_node_sequence_configs` on the server).
 *
 * IMPORTANT: we intentionally do NOT bind `:style="{ width, height }"` to
 * `data.width` / `data.height`. `rete-scopes-plugin`'s `resizeParent`
 * mutates the plain class properties `node.width` / `node.height` and then
 * calls `area.resize(nodeId, w, h)`, which writes inline `width`/`height`
 * directly onto our root element (see `rete-area-plugin`). A `:style`
 * binding would cache the stale initial value (Vue doesn't track plain
 * class-property writes) and clobber the DOM writes from the area plugin,
 * keeping the sequence pinned at the server-default `300x200` from
 * `sequence_config.ex`. Regular nodes follow the same pattern:
 * `FlowNode.vue` never binds `:style` either. See
 * `project_flow_sequences_bugs_2026_04_24.md` addendum for the debug
 * trail.
 *
 * Config panel, tracks display, and backdrop preview ship in later phases.
 */

import { computed, inject } from "vue";

import type { FlowNode } from "../lib/flow-node";
import { FLOW_CONTEXT_KEY } from "../setup";
import { reparentGestureActive } from "../lib/flow-reparent-state";

interface FlowContextValue {
  selectedReteIds: Set<string | number>;
}

const { data } = defineProps<{
  data: FlowNode;
  emit?: (event: string, payload?: unknown) => void;
  seed?: number;
}>();

const ctx = inject<FlowContextValue>(FLOW_CONTEXT_KEY, {
  selectedReteIds: new Set<string | number>(),
});

const label = computed(() => (data.nodeData?.name as string) || "");

const isSelected = computed(() => ctx.selectedReteIds.has(data?.id));

// Drop-target highlight: lit up whenever a reparent gesture is in-flight
// (Cmd/Ctrl held AND a drag is active) AND this sequence is NOT itself in
// the moving selection — you can't drop into yourself.
const isDropTarget = computed(
  () => reparentGestureActive.value && !ctx.selectedReteIds.has(data?.id),
);
</script>

<template>
  <div
    class="flow-sequence"
    :class="{
      'flow-sequence--selected': isSelected,
      'flow-sequence--drop-target': isDropTarget,
    }"
    data-testid="flow-sequence"
  >
    <header class="flow-sequence-header">
      <span class="flow-sequence-label">{{ label }}</span>
    </header>
  </div>
</template>

<style scoped>
.flow-sequence {
  border: 2px dashed hsl(var(--primary) / 0.5);
  border-radius: 0.5rem;
  background: hsl(var(--primary) / 0.04);
  box-sizing: border-box;
  pointer-events: all;
  position: relative;
  transition:
    box-shadow 150ms ease,
    background-color 120ms ease,
    border-color 120ms ease;
}

.flow-sequence--selected {
  box-shadow:
    0 0 0 2px hsl(var(--background)),
    0 0 0 4px hsl(var(--primary));
}

/* Reparent drop target — brighter background + solid border signals
   "drop here to re-assign parent". Works alongside .flow-sequence--selected
   (both can coexist; selected outline remains, drop-target recolors the
   fill). */
.flow-sequence--drop-target {
  background: hsl(var(--primary) / 0.18);
  border-style: solid;
  border-color: hsl(var(--primary));
}

.flow-sequence-header {
  position: absolute;
  top: -0.75rem;
  left: 0.75rem;
  padding: 0 0.5rem;
  background: hsl(var(--background));
  color: hsl(var(--primary));
  font-size: 0.7rem;
  font-weight: 500;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

.flow-sequence-label {
  user-select: none;
}
</style>
