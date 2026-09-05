<script setup lang="ts">
import { MessageCircle, Plus } from "@lucide/vue";
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import { commentPopoverPosition } from "@components/comments/commentGeometry";
import { useLive } from "@shared/composables/useLive";
import { useSheetCanvasComments } from "../../composables/useSheetCanvasComments";
import type { SheetCommentsPanelState, SheetCommentThread } from "../../types/comments";
import SheetCommentsPanel from "../panels/SheetCommentsPanel.vue";

const {
  container,
  state,
  commentPins,
  focusThreadId,
  draftStorageKey = null,
} = defineProps<{
  container: () => HTMLElement | null;
  state: SheetCommentsPanelState;
  commentPins: SheetCommentThread[];
  focusThreadId: number | null;
  draftStorageKey?: string | null;
}>();
const emit = defineEmits<{
  interactionChange: [active: boolean];
}>();

function resolveContainer(): HTMLElement | null {
  return container();
}

const live = useLive();
const commentLayer = ref<HTMLElement | null>(null);
const popup = ref<HTMLElement | null>(null);
const contextMenu = ref<HTMLElement | null>(null);
const focusWithin = ref(false);
const measuredPopupSize = ref<{ width: number; height: number } | null>(null);
let focusLeaveTimer: ReturnType<typeof setTimeout> | null = null;
let popupResizeObserver: ResizeObserver | null = null;
const {
  pins,
  placing,
  visibleBounds,
  hoverId,
  hoveredPin,
  activePoint,
  draftPoint,
  moveError,
  contextMenuPoint,
  dragging,
  selectThread,
  startDrag,
  movePinWithKeyboard,
  placeContextComment,
  closeContextMenu,
} = useSheetCanvasComments({
  container: resolveContainer,
  state: () => state,
  pins: () => commentPins,
  focusThreadId: () => focusThreadId,
  draftStorageKey: () => draftStorageKey,
  live,
});

const popupOpen = computed(
  () => state.open && state.presentation === "canvas" && Boolean(activePoint.value),
);
const popupSize = computed(() => ({
  width: Math.max(0, Math.min(360, visibleBounds.value.width - 24)),
  height: Math.max(0, Math.min(480, visibleBounds.value.height - 24)),
}));

const popupPlacementSize = computed(() => measuredPopupSize.value ?? popupSize.value);

function positionWithinVisibleSurface(
  point: { x: number; y: number },
  size: { width: number; height: number },
) {
  const visible = visibleBounds.value;
  const position = commentPopoverPosition(
    { x: point.x, y: point.y - visible.top },
    { width: visible.width, height: visible.height },
    size,
  );
  return { x: position.x, y: position.y + visible.top };
}

function popupPositionWithinVisibleSurface(
  point: { x: number; y: number },
  size: { width: number; height: number },
) {
  const visible = visibleBounds.value;
  const relativePoint = { x: point.x, y: point.y - visible.top };
  const horizontal = commentPopoverPosition(
    relativePoint,
    { width: visible.width, height: visible.height },
    size,
  );
  const margin = 12;
  const pinGap = 24;
  const alignedTop = relativePoint.y - 18;
  const maxTop = Math.max(margin, visible.height - size.height - margin);
  const preferredTop =
    alignedTop + size.height <= visible.height - margin
      ? alignedTop
      : relativePoint.y - size.height - pinGap;

  return {
    x: horizontal.x,
    y: Math.max(margin, Math.min(preferredTop, maxTop)) + visible.top,
  };
}

const popupPosition = computed(() =>
  popupPositionWithinVisibleSurface(
    activePoint.value ?? {
      x: visibleBounds.value.width / 2,
      y: visibleBounds.value.top + visibleBounds.value.height / 2,
    },
    popupPlacementSize.value,
  ),
);
const previewSize = computed(() => ({
  width: Math.max(0, Math.min(260, visibleBounds.value.width - 24)),
  height: Math.max(0, Math.min(112, visibleBounds.value.height - 24)),
}));
const previewPosition = computed(() =>
  positionWithinVisibleSurface(hoveredPin.value?.screen ?? { x: 0, y: 0 }, previewSize.value),
);
const contextMenuPosition = computed(() => {
  const point = contextMenuPoint.value ?? { x: 0, y: 0 };
  const visible = visibleBounds.value;
  return {
    x: Math.max(8, Math.min(point.x, visible.width - 200)),
    y: Math.max(visible.top + 8, Math.min(point.y, visible.top + visible.height - 48)),
  };
});
const localInteractionActive = computed(
  () => Boolean(contextMenuPoint.value) || dragging.value || focusWithin.value,
);

function onFocusIn(): void {
  if (focusLeaveTimer) {
    clearTimeout(focusLeaveTimer);
    focusLeaveTimer = null;
  }
  focusWithin.value = true;
}

function syncFocusContainment(root = commentLayer.value): void {
  if (focusLeaveTimer) {
    clearTimeout(focusLeaveTimer);
    focusLeaveTimer = null;
  }
  focusWithin.value = Boolean(root?.contains(document.activeElement));
}

function scheduleFocusContainmentCheck(root = commentLayer.value): void {
  if (focusLeaveTimer) clearTimeout(focusLeaveTimer);
  focusLeaveTimer = setTimeout(() => {
    focusLeaveTimer = null;
    focusWithin.value = Boolean(root?.contains(document.activeElement));
  });
}

function onFocusOut(event: FocusEvent): void {
  const root = event.currentTarget as HTMLElement;
  const nextTarget = event.relatedTarget;
  if (nextTarget instanceof Node && root.contains(nextTarget)) return;
  scheduleFocusContainmentCheck(root);
}

function restoreFocusAfterPopup(previousId: number | null | undefined): void {
  const previousPin =
    previousId == null ? null : document.getElementById(`sheet-comment-pin-${previousId}`);
  const target =
    previousPin ?? document.getElementById("sheet-comments-toggle") ?? resolveContainer();
  target?.focus({ preventScroll: true });
}

function stopObservingPopup(): void {
  popupResizeObserver?.disconnect();
  popupResizeObserver = null;
}

function measurePopup(): void {
  const element = popup.value;
  if (!element) return;
  const rect = element.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return;
  const nextSize = { width: rect.width, height: rect.height };
  if (
    measuredPopupSize.value?.width === nextSize.width &&
    measuredPopupSize.value.height === nextSize.height
  )
    return;
  measuredPopupSize.value = nextSize;
}

function observePopup(): void {
  stopObservingPopup();
  measurePopup();
  if (!popup.value) return;
  popupResizeObserver = new ResizeObserver(measurePopup);
  popupResizeObserver.observe(popup.value);
}

watch([popupOpen, () => state.thread?.id], async ([open], [previousOpen, previousId]) => {
  if (open) {
    await nextTick();
    observePopup();
    popup.value?.focus({ preventScroll: true });
  } else if (previousOpen) {
    stopObservingPopup();
    measuredPopupSize.value = null;
    await nextTick();
    restoreFocusAfterPopup(previousId);
    syncFocusContainment();
  }
});

onMounted(async () => {
  if (!popupOpen.value) return;
  await nextTick();
  observePopup();
  popup.value?.focus({ preventScroll: true });
});

watch(localInteractionActive, (active) => emit("interactionChange", active), {
  immediate: true,
  flush: "sync",
});

watch(contextMenuPoint, async (point) => {
  if (!point) {
    await nextTick();
    syncFocusContainment();
    return;
  }
  await nextTick();
  contextMenu.value?.querySelector<HTMLElement>("button")?.focus({ preventScroll: true });
});

watch(
  [
    () => pins.value.map((pin) => pin.thread.id).join(","),
    () => Boolean(draftPoint.value),
    popupOpen,
    () => Boolean(contextMenuPoint.value),
  ],
  async () => {
    await nextTick();
    scheduleFocusContainmentCheck();
  },
);

onUnmounted(() => {
  if (focusLeaveTimer) clearTimeout(focusLeaveTimer);
  stopObservingPopup();
  emit("interactionChange", false);
});
</script>

<template>
  <div
    ref="commentLayer"
    class="pointer-events-none absolute inset-0 z-20 overflow-visible"
    data-testid="sheet-canvas-comments"
    data-sheet-comment-ui="true"
    @focusin="onFocusIn"
    @focusout="onFocusOut"
  >
    <p id="sheet-comment-pin-keyboard-instructions" class="sr-only">
      {{ $t("sheets.comments.keyboard_move_hint") }}
    </p>
    <p v-if="placing" id="sheet-comment-surface-keyboard-instructions" class="sr-only">
      {{ $t("sheets.comments.keyboard_place_hint") }}
    </p>
    <p
      v-if="placing"
      role="status"
      class="sticky left-1/2 top-4 z-10 w-max -translate-x-1/2 rounded-full border border-border bg-popover px-4 py-2 text-xs text-popover-foreground shadow-md"
    >
      {{ $t("sheets.comments.placing_hint") }}
    </p>
    <p
      v-if="moveError"
      role="alert"
      class="sticky left-1/2 top-4 z-10 w-max -translate-x-1/2 rounded-md border border-destructive/30 bg-popover px-4 py-2 text-xs text-destructive"
    >
      {{ $t("sheets.comments.update_failed") }}
    </p>

    <button
      v-for="pin in pins"
      :id="`sheet-comment-pin-${pin.thread.id}`"
      :key="pin.thread.id"
      type="button"
      class="pointer-events-auto absolute flex size-8 -translate-x-1/2 -translate-y-1/2 touch-none items-center justify-center rounded-full rounded-bl-sm border-2 border-background bg-primary text-primary-foreground shadow-md transition-[background-color,transform] hover:scale-105 hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
      :class="{
        'ring-2 ring-ring ring-offset-2': state.thread?.id === pin.thread.id && popupOpen,
        'cursor-grab active:cursor-grabbing': state.canComment,
      }"
      :style="{ left: `${pin.screen.x}px`, top: `${pin.screen.y}px` }"
      :aria-label="$t('sheets.comments.pin_label', { author: pin.thread.author.display_name })"
      :aria-describedby="
        hoverId === pin.thread.id && !(popupOpen && state.thread?.id === pin.thread.id)
          ? 'sheet-comment-preview sheet-comment-pin-keyboard-instructions'
          : 'sheet-comment-pin-keyboard-instructions'
      "
      :aria-expanded="state.thread?.id === pin.thread.id && popupOpen"
      aria-haspopup="dialog"
      @pointerdown.stop="startDrag($event, pin.thread)"
      @pointerenter="hoverId = pin.thread.id"
      @pointerleave="hoverId = null"
      @focus="hoverId = pin.thread.id"
      @blur="hoverId = null"
      @click.stop="selectThread(pin.thread, $event)"
      @keydown="movePinWithKeyboard($event, pin.thread)"
    >
      <MessageCircle class="size-4" />
    </button>

    <button
      v-if="draftPoint"
      id="sheet-comment-draft-pin"
      type="button"
      class="pointer-events-auto absolute flex size-8 -translate-x-1/2 -translate-y-1/2 touch-none cursor-grab items-center justify-center rounded-full rounded-bl-sm border-2 border-background bg-primary text-primary-foreground shadow-md ring-2 ring-primary/40 active:cursor-grabbing"
      :style="{ left: `${draftPoint.x}px`, top: `${draftPoint.y}px` }"
      :aria-label="$t('sheets.comments.move_pin')"
      aria-describedby="sheet-comment-pin-keyboard-instructions"
      @pointerdown.stop="startDrag($event, null)"
      @keydown="movePinWithKeyboard($event, null)"
    >
      <Plus class="size-4" />
    </button>

    <div
      v-if="hoveredPin && !(popupOpen && state.thread?.id === hoveredPin.thread.id)"
      id="sheet-comment-preview"
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
      id="sheet-comment-context-menu"
      ref="contextMenu"
      role="menu"
      :aria-label="$t('sheets.comments.context_menu')"
      class="pointer-events-auto absolute w-48 rounded-md border border-border bg-popover p-1 text-popover-foreground shadow-lg outline-none"
      :style="{
        left: `${contextMenuPosition.x}px`,
        top: `${contextMenuPosition.y}px`,
      }"
      @contextmenu.prevent.stop
    >
      <button
        id="sheet-comment-context-add"
        type="button"
        role="menuitem"
        class="flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-left text-sm outline-none transition-colors hover:bg-accent focus:bg-accent"
        @click="placeContextComment"
        @keydown.escape.prevent.stop="closeContextMenu"
      >
        <MessageCircle class="size-4 text-muted-foreground" />
        {{ $t("sheets.comments.add_comment") }}
      </button>
    </div>

    <div
      v-if="popupOpen"
      id="sheet-comment-popover"
      ref="popup"
      role="dialog"
      tabindex="-1"
      :aria-label="$t('sheets.comments.title')"
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
      <SheetCommentsPanel :state="state" :draft-storage-key="draftStorageKey" embedded />
    </div>
  </div>
</template>
