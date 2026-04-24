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
 * Config panel (image + audio tracks) ships in a later slice.
 */

import { computed, inject, nextTick, ref, useTemplateRef, watch } from "vue";

import { useLive } from "@composables/useLive";
import type { FlowNode } from "../lib/flow-node";
import { FLOW_CONTEXT_KEY } from "../setup";
import { reparentGestureActive } from "../lib/flow-reparent-state";

interface FlowContextValue {
  selectedReteIds: Set<string | number>;
  canEdit: boolean;
  zoom: number;
  /** Bumped on remote node/sequence updates and on local optimistic
   * writes. `FlowNode` is a plain class, so mutating `nodeData.name` on
   * the instance isn't Vue-reactive; reading this counter in a computed
   * creates the dependency that forces re-render. */
  nodeDataVersion: number;
}

const { data } = defineProps<{
  data: FlowNode;
  emit?: (event: string, payload?: unknown) => void;
  seed?: number;
}>();

const ctx = inject<FlowContextValue>(FLOW_CONTEXT_KEY, {
  selectedReteIds: new Set<string | number>(),
  canEdit: false,
  zoom: 1,
  nodeDataVersion: 0,
});

const live = useLive();

const label = computed(() => {
  // eslint-disable-next-line @typescript-eslint/no-unused-expressions
  ctx.nodeDataVersion; // reactivity dep — see FlowContextValue comment.
  return (data.nodeData?.name as string) || "";
});

const isSelected = computed(() => ctx.selectedReteIds.has(data?.id));

// Drop-target highlight: lit up whenever a reparent gesture is in-flight
// (Cmd/Ctrl held AND a drag is active) AND this sequence is NOT itself in
// the moving selection — you can't drop into yourself.
const isDropTarget = computed(
  () => reparentGestureActive.value && !ctx.selectedReteIds.has(data?.id),
);

// Toolbar visible only for a single-sequence selection and only when the
// user can edit. Multi-select hides it (bulk rename doesn't make sense).
const showToolbar = computed(
  () => ctx.canEdit && ctx.selectedReteIds.size === 1 && isSelected.value,
);

// Raw DB id (rete ids are prefixed `node-`, we need the bare integer for
// server events).
const sequenceDbId = computed(() => {
  const reteId = String(data?.id || "");
  return reteId.startsWith("node-") ? reteId.slice(5) : reteId;
});

// Inverse scale compensates the canvas zoom so the toolbar stays at a
// constant screen size. Same pattern as `FlowNodeToolbar.vue`.
const inverseScale = computed(() => 1 / (ctx.zoom || 1));

// Local editing buffer. Seeded from `label` whenever the toolbar opens or
// the canonical value changes (remote rename via collab broadcast).
const draftName = ref(label.value);
const inputRef = useTemplateRef<HTMLInputElement>("nameInput");

watch(label, (next) => {
  // Don't clobber what the user is actively typing. If the input is
  // focused, leave the buffer alone — blur or Enter will commit, and a
  // fresh remote value will overwrite on next focus.
  if (document.activeElement !== inputRef.value) {
    draftName.value = next;
  }
});

watch(showToolbar, async (next) => {
  if (next) {
    draftName.value = label.value;
    await nextTick();
    // Don't autofocus — selecting a sequence shouldn't steal focus from
    // wherever the user was typing. They click the input to edit.
  }
});

function commitName() {
  const trimmed = draftName.value.trim();
  if (!trimmed || trimmed === label.value) {
    // Revert empty / unchanged — nothing to push.
    draftName.value = label.value;
    return;
  }
  // Optimistic local update — the server broadcast skips self
  // (`broadcast_from`), so without this the local header label would
  // stay stale until the next reload. Bump `nodeDataVersion` so the
  // computed `label` picks up the change (FlowNode instance fields
  // aren't Vue-reactive on their own).
  data.nodeData = { ...data.nodeData, name: trimmed };
  ctx.nodeDataVersion = (ctx.nodeDataVersion || 0) + 1;

  live.pushEvent("update_sequence_name", {
    id: sequenceDbId.value,
    name: trimmed,
  });
}

function cancelEdit(event: KeyboardEvent) {
  draftName.value = label.value;
  (event.target as HTMLInputElement | null)?.blur();
}
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

    <!-- Floating toolbar. `.stop` on pointer/mouse events prevents the
         canvas drag/marquee from triggering while the user interacts
         with the input. -->
    <div
      v-if="showToolbar"
      class="flow-sequence-toolbar"
      :style="{
        transform: `translateX(-50%) scale(${inverseScale})`,
        transformOrigin: 'bottom center',
        marginBottom: `${8 * inverseScale}px`,
      }"
      @pointerdown.stop
      @mousedown.stop
      @click.stop
    >
      <input
        ref="nameInput"
        v-model="draftName"
        type="text"
        class="flow-sequence-name-input"
        :placeholder="$t('flows.sequences.name_placeholder')"
        data-testid="flow-sequence-name-input"
        @keydown.enter.prevent="($event.target as HTMLInputElement).blur()"
        @keydown.escape.prevent="cancelEdit"
        @blur="commitName"
      />
    </div>
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

/* Floating toolbar above the sequence bbox. Mirrors FlowNodeToolbar's
   positioning (`absolute bottom-full left-1/2`, inverse-scaled for zoom
   compensation). Only contains the name input for now. */
.flow-sequence-toolbar {
  position: absolute;
  bottom: 100%;
  left: 50%;
  z-index: 30;
  display: flex;
  align-items: center;
  gap: 0.375rem;
  padding: 0.375rem 0.5rem;
  background: hsl(var(--background));
  border: 1px solid hsl(var(--border));
  border-radius: 0.375rem;
  box-shadow: 0 2px 8px hsl(0 0% 0% / 0.25);
  pointer-events: auto;
  white-space: nowrap;
}

.flow-sequence-name-input {
  all: unset;
  min-width: 12rem;
  padding: 0.25rem 0.5rem;
  font-size: 0.75rem;
  color: hsl(var(--foreground));
  background: transparent;
  border-radius: 0.25rem;
  transition: background-color 120ms ease;
}

.flow-sequence-name-input:focus {
  background: hsl(var(--muted) / 0.4);
}

.flow-sequence-name-input::placeholder {
  color: hsl(var(--muted-foreground));
}
</style>
