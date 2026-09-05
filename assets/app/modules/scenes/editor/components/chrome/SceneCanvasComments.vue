<script setup lang="ts">
import { MessageCircle, Plus } from "@lucide/vue";
import { computed, nextTick, ref, watch } from "vue";
import { useLive } from "@shared/composables/useLive";
import { commentPopoverPosition } from "@components/comments/commentGeometry";
import type { SceneCommentsPanelState, SceneCommentThread } from "../../../types/comments";
import type {
  SceneCommentProjection,
  SceneCommentStageTransform,
} from "../../lib/comment-geometry";
import { useSceneCanvasComments } from "../../composables/useSceneCanvasComments";
import SceneCommentsPanel from "../panels/SceneCommentsPanel.vue";

const { container, stage, projection, backgroundSettled, state, commentPins, focusThreadId } =
  defineProps<{
    container: HTMLElement;
    stage: SceneCommentStageTransform;
    projection: SceneCommentProjection;
    backgroundSettled: boolean;
    state: SceneCommentsPanelState;
    commentPins: SceneCommentThread[];
    focusThreadId: number | null;
  }>();

const live = useLive();
const popup = ref<HTMLElement | null>(null);
const contextMenu = ref<HTMLElement | null>(null);
const {
  pins,
  placing,
  bounds,
  hoverId,
  hoveredPin,
  activePoint,
  draftPoint,
  moveError,
  contextMenuPoint,
  selectThread,
  startDrag,
  placeContextComment,
  closeContextMenu,
} = useSceneCanvasComments({
  container,
  stage,
  projection,
  backgroundSettled: () => backgroundSettled,
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
const contextMenuPosition = computed(() => {
  const point = contextMenuPoint.value ?? { x: 0, y: 0 };
  return {
    x: Math.max(8, Math.min(point.x, bounds.value.width - 188)),
    y: Math.max(8, Math.min(point.y, bounds.value.height - 48)),
  };
});

watch([popupOpen, () => state.thread?.id], async ([open], [previousOpen, previousId]) => {
  if (open) {
    await nextTick();
    popup.value?.focus({ preventScroll: true });
  } else if (previousOpen && previousId != null) {
    await nextTick();
    document.getElementById(`scene-comment-pin-${previousId}`)?.focus({ preventScroll: true });
  }
});

watch(contextMenuPoint, async (point) => {
  if (!point) return;
  await nextTick();
  contextMenu.value?.querySelector<HTMLElement>("button")?.focus({ preventScroll: true });
});
</script>

<template>
  <div
    class="pointer-events-none absolute inset-0 z-20 overflow-hidden"
    data-testid="scene-canvas-comments"
    data-scene-comment-ui="true"
  >
    <p
      v-if="placing"
      role="status"
      class="absolute left-1/2 top-4 -translate-x-1/2 rounded-full border border-border bg-popover px-4 py-2 text-xs text-popover-foreground shadow-md"
    >
      {{ $t("scenes.comments.placing_hint") }}
    </p>
    <p
      v-if="moveError"
      role="alert"
      class="absolute left-1/2 top-4 -translate-x-1/2 rounded-md border border-destructive/30 bg-popover px-4 py-2 text-xs text-destructive"
    >
      {{ $t("scenes.comments.update_failed") }}
    </p>

    <button
      v-for="pin in pins"
      :id="`scene-comment-pin-${pin.thread.id}`"
      :key="pin.thread.id"
      type="button"
      class="pointer-events-auto absolute flex size-8 -translate-x-1/2 -translate-y-1/2 touch-none items-center justify-center rounded-full rounded-bl-sm border-2 border-background bg-primary text-primary-foreground shadow-md transition-colors hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
      :class="{
        'ring-2 ring-ring ring-offset-2': state.thread?.id === pin.thread.id && popupOpen,
        'cursor-grab active:cursor-grabbing': state.canComment,
      }"
      :style="{ left: `${pin.screen.x}px`, top: `${pin.screen.y}px` }"
      :aria-label="$t('scenes.comments.pin_label', { author: pin.thread.author.display_name })"
      :aria-describedby="hoverId === pin.thread.id ? 'scene-comment-preview' : undefined"
      :aria-expanded="state.thread?.id === pin.thread.id && popupOpen"
      aria-haspopup="dialog"
      @pointerdown.stop="startDrag($event, pin.thread)"
      @pointerenter="hoverId = pin.thread.id"
      @pointerleave="hoverId = null"
      @focus="hoverId = pin.thread.id"
      @blur="hoverId = null"
      @click.stop="selectThread(pin.thread, $event)"
    >
      <MessageCircle class="size-4" />
    </button>

    <button
      v-if="draftPoint"
      id="scene-comment-draft-pin"
      type="button"
      class="pointer-events-auto absolute flex size-8 -translate-x-1/2 -translate-y-1/2 touch-none cursor-grab items-center justify-center rounded-full rounded-bl-sm border-2 border-background bg-primary text-primary-foreground shadow-md ring-2 ring-primary/40 active:cursor-grabbing"
      :style="{ left: `${draftPoint.x}px`, top: `${draftPoint.y}px` }"
      :aria-label="$t('scenes.comments.move_pin')"
      @pointerdown.stop="startDrag($event, null)"
    >
      <Plus class="size-4" />
    </button>

    <div
      v-if="hoveredPin && !(popupOpen && state.thread?.id === hoveredPin.thread.id)"
      id="scene-comment-preview"
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
      v-if="contextMenuPoint"
      id="scene-comment-context-menu"
      ref="contextMenu"
      role="menu"
      :aria-label="$t('scenes.comments.context_menu')"
      class="pointer-events-auto absolute w-45 rounded-md border border-border bg-popover p-1 text-popover-foreground shadow-lg outline-none"
      :style="{
        left: `${contextMenuPosition.x}px`,
        top: `${contextMenuPosition.y}px`,
      }"
      @contextmenu.prevent.stop
    >
      <button
        id="scene-comment-context-add"
        type="button"
        role="menuitem"
        class="flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-left text-sm outline-none transition-colors hover:bg-accent focus:bg-accent"
        @click="placeContextComment"
        @keydown.escape.prevent.stop="closeContextMenu"
      >
        <MessageCircle class="size-4 text-muted-foreground" />
        {{ $t("scenes.comments.add_comment") }}
      </button>
    </div>

    <div
      v-if="popupOpen"
      id="scene-comment-popover"
      ref="popup"
      role="dialog"
      tabindex="-1"
      :aria-label="$t('scenes.comments.title')"
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
      <SceneCommentsPanel :state="state" embedded />
    </div>
  </div>
</template>
