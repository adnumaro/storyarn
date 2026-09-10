<script setup lang="ts">
import { Magnet, MessageCircle, Plus, Unlink, Repeat2 } from "@lucide/vue";
import { computed, nextTick, ref, watch } from "vue";
import type { AreaPlugin } from "rete-area-plugin";
import type { FlowAreaExtra, FlowSchemes } from "../../lib/rete-schemes";
import type { FlowCommentsPanelState, FlowCommentThread } from "../../../types/comments";
import { useLive } from "@shared/composables/useLive";
import { commentPopoverPosition } from "../../lib/comment-geometry";
import { useCanvasComments } from "../../composables/useCanvasComments";
import FlowCommentsPanel from "../panels/FlowCommentsPanel.vue";

const { area, container, state, commentPins, focusThreadId } = defineProps<{
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  container: HTMLElement;
  state: FlowCommentsPanelState;
  commentPins: FlowCommentThread[];
  focusThreadId: number | null;
}>();
const live = useLive();
const popup = ref<HTMLElement | null>(null);
const {
  pins,
  placing,
  bounds,
  hoverId,
  hoveredPin,
  activePoint,
  draftPoint,
  moveError,
  panelState,
  magnetism,
  moving,
  dragPreview,
  snapOutline,
  isPending,
  onPinKeyDown,
  onPinBlur,
  onLostCapture,
  toggleMagnetism,
  cycleContext,
  selectThread,
  startDrag,
} = useCanvasComments({
  area,
  container,
  state: () => state,
  pins: () => commentPins,
  focusThreadId: () => focusThreadId,
  live,
});
const popupOpen = computed(
  () => state.open && state.presentation === "canvas" && Boolean(activePoint.value),
);
const popupSize = computed(() => ({
  width: Math.max(0, Math.min(360, bounds.value.width - 24)),
  height: Math.max(0, Math.min(480, bounds.value.height - 24)),
}));
const popupPosition = computed(() =>
  commentPopoverPosition(
    activePoint.value ?? { x: bounds.value.width / 2, y: bounds.value.height / 2 },
    bounds.value,
    popupSize.value,
  ),
);
const previewSize = computed(() => ({
  width: Math.max(0, Math.min(260, bounds.value.width - 24)),
  height: 112,
}));
const previewPosition = computed(() =>
  commentPopoverPosition(
    hoveredPin.value?.screen ?? { x: 0, y: 0 },
    bounds.value,
    previewSize.value,
  ),
);
watch([popupOpen, () => state.thread?.id], async ([open], [previousOpen, previousId]) => {
  if (open) {
    await nextTick();
    popup.value?.focus({ preventScroll: true });
  } else if (previousOpen && previousId != null) {
    await nextTick();
    document.getElementById(`flow-comment-pin-${previousId}`)?.focus({ preventScroll: true });
  }
});
</script>

<template>
  <div
    class="pointer-events-none absolute inset-0 z-20 overflow-hidden"
    data-testid="flow-canvas-comments"
  >
    <div
      v-if="state.canComment && (pins.length || placing || draftPoint)"
      class="pointer-events-auto absolute right-4 top-4 z-10 flex items-center gap-2"
      @pointerdown.stop
    >
      <button
        id="flow-comment-magnetism-toggle"
        type="button"
        class="flex items-center gap-1.5 rounded-full border border-border bg-popover px-3 py-2 text-xs text-popover-foreground shadow-md transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        :aria-pressed="magnetism"
        :title="$t('flows.comments.magnetism_hint')"
        @click.stop="toggleMagnetism"
      >
        <Magnet v-if="magnetism" class="size-3.5" /><Unlink v-else class="size-3.5" />
        {{ $t(magnetism ? "flows.comments.magnetism_on" : "flows.comments.magnetism_off") }}
      </button>
    </div>
    <p id="flow-comment-move-instructions" class="sr-only">
      {{ $t("flows.comments.keyboard_move_hint") }}
    </p>
    <div
      v-if="moving && snapOutline"
      class="absolute rounded-lg border-2 border-primary bg-primary/5"
      :style="{
        left: `${snapOutline.left}px`,
        top: `${snapOutline.top}px`,
        width: `${snapOutline.width}px`,
        height: `${snapOutline.height}px`,
      }"
    />
    <div
      v-if="moving"
      id="flow-comment-snap-preview"
      role="status"
      aria-live="polite"
      class="absolute bottom-5 left-1/2 flex max-w-[90%] -translate-x-1/2 items-center gap-2 rounded-lg border border-border bg-popover px-3 py-2 text-xs text-popover-foreground shadow-md"
    >
      <span class="truncate">{{
        dragPreview?.candidate
          ? $t("flows.comments.snap_context", { label: dragPreview.candidate.label })
          : $t("flows.comments.free_position")
      }}</span>
      <button
        v-if="(dragPreview?.candidates.length ?? 0) > 1"
        type="button"
        class="pointer-events-auto inline-flex shrink-0 items-center gap-1 rounded-md px-2 py-1 hover:bg-accent focus-visible:ring-2 focus-visible:ring-ring"
        @pointerdown.stop.prevent
        @click.stop="cycleContext(1)"
      >
        <Repeat2 class="size-3.5" />{{ $t("flows.comments.next_context") }}
      </button>
      <span class="hidden text-muted-foreground sm:inline">{{
        $t("flows.comments.drag_hint")
      }}</span>
    </div>
    <p
      v-if="placing"
      id="flow-comment-placement-hint"
      role="status"
      class="absolute left-1/2 top-4 -translate-x-1/2 rounded-full border border-border bg-popover px-4 py-2 text-xs text-popover-foreground shadow-md"
    >
      {{ $t("flows.comments.placing_hint") }}
    </p>
    <p
      v-if="moveError"
      role="alert"
      class="absolute left-1/2 top-4 -translate-x-1/2 rounded-md border border-destructive/30 bg-popover px-4 py-2 text-xs text-destructive"
    >
      {{ $t("flows.comments.update_failed") }}
    </p>
    <button
      v-for="pin in pins"
      :id="`flow-comment-pin-${pin.thread.id}`"
      :key="pin.thread.id"
      type="button"
      class="pointer-events-auto absolute flex size-8 -translate-x-1/2 -translate-y-1/2 touch-none items-center justify-center rounded-full rounded-bl-sm border-2 border-background bg-primary text-primary-foreground shadow-md transition-colors hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
      :class="{
        'ring-2 ring-ring ring-offset-2': state.thread?.id === pin.thread.id && popupOpen,
        'cursor-grab active:cursor-grabbing': state.canComment,
      }"
      :style="{ left: `${pin.screen.x}px`, top: `${pin.screen.y}px` }"
      :aria-label="$t('flows.comments.pin_label', { author: pin.thread.author.display_name })"
      :aria-describedby="
        hoverId === pin.thread.id
          ? 'flow-comment-preview flow-comment-move-instructions'
          : 'flow-comment-move-instructions'
      "
      :aria-busy="isPending(pin.thread.id)"
      :aria-expanded="state.thread?.id === pin.thread.id && popupOpen"
      aria-haspopup="dialog"
      @pointerdown.stop="startDrag($event, pin.thread)"
      @keydown="onPinKeyDown($event, pin.thread)"
      @lostpointercapture="onLostCapture"
      @pointerenter="hoverId = pin.thread.id"
      @pointerleave="hoverId = null"
      @focus="hoverId = pin.thread.id"
      @blur="onPinBlur"
      @click.stop="selectThread(pin.thread, $event)"
    >
      <MessageCircle class="size-4" />
    </button>

    <button
      v-if="draftPoint"
      id="flow-comment-draft-pin"
      type="button"
      class="pointer-events-auto absolute flex size-8 -translate-x-1/2 -translate-y-1/2 touch-none cursor-grab items-center justify-center rounded-full rounded-bl-sm border-2 border-background bg-primary text-primary-foreground shadow-md ring-2 ring-primary/40 active:cursor-grabbing"
      :style="{ left: `${draftPoint.x}px`, top: `${draftPoint.y}px` }"
      :aria-label="$t('flows.comments.move_pin')"
      aria-describedby="flow-comment-move-instructions"
      :aria-busy="panelState.draftPending"
      @pointerdown.stop="startDrag($event, null)"
      @keydown="onPinKeyDown($event, null)"
      @blur="onPinBlur"
      @lostpointercapture="onLostCapture"
    >
      <Plus class="size-4" />
    </button>

    <div
      v-if="hoveredPin && !(popupOpen && state.thread?.id === hoveredPin.thread.id)"
      id="flow-comment-preview"
      role="tooltip"
      class="absolute rounded-xl border border-border bg-popover p-3 text-popover-foreground shadow-xl"
      :style="{
        left: `${previewPosition.x}px`,
        top: `${previewPosition.y}px`,
        width: `${previewSize.width}px`,
      }"
    >
      <p class="truncate text-xs font-semibold">{{ hoveredPin.thread.author.display_name }}</p>
      <p class="mt-1.5 line-clamp-3 whitespace-pre-wrap break-words text-xs text-muted-foreground">
        {{ hoveredPin.thread.preview }}
      </p>
    </div>

    <div
      v-if="popupOpen"
      id="flow-comment-popover"
      ref="popup"
      role="dialog"
      tabindex="-1"
      :aria-label="$t('flows.comments.title')"
      class="pointer-events-auto absolute flex flex-col overflow-hidden rounded-xl border border-border bg-popover text-popover-foreground shadow-xl outline-none"
      :style="{
        left: `${popupPosition.x}px`,
        top: `${popupPosition.y}px`,
        width: `${popupSize.width}px`,
        maxHeight: `${popupSize.height}px`,
      }"
      @pointerdown.stop
      @wheel.stop
      @contextmenu.stop
    >
      <FlowCommentsPanel :state="panelState" embedded />
    </div>
  </div>
</template>
