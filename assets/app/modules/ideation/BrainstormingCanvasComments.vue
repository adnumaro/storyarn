<script setup lang="ts">
import { computed, nextTick, onUnmounted, ref, shallowRef, watch } from "vue";
import { MessageCircle, Plus } from "@lucide/vue";
import { useLive } from "@shared/composables/useLive";
import { commentPopoverPosition } from "@components/comments/commentGeometry";
import type { CommentPosition, CommentThread } from "@components/comments/types";
import BrainstormingCommentPopover from "./BrainstormingCommentPopover.vue";
import type { BrainstormingCommentsState } from "./commentTypes";
import type { CanvasIdea, IdeaGroup } from "./types";

const { state, view, epoch, sessionId, baseUrl, notes, groups } = defineProps<{
  state: BrainstormingCommentsState;
  view: { x: number; y: number; zoom: number; width: number; height: number };
  epoch: string;
  sessionId: number;
  baseUrl: string;
  notes: CanvasIdea[];
  groups: IdeaGroup[];
}>();
const emit = defineEmits<{ focus: [point: CommentPosition] }>();
const live = useLive();
const popup = ref<HTMLElement | null>(null);
const popupSize = ref({ width: 360, height: 400 });
const hoverId = ref<number | null>(null);
const moveError = ref(false);
const pending = ref(false);
const optimistic = shallowRef<{ id: number | null; position: CommentPosition } | null>(null);
interface Drag {
  thread: CommentThread | null;
  target: HTMLElement;
  pointerId: number | null;
  start: CommentPosition;
  origin: CommentPosition;
  position: CommentPosition;
  moved: boolean;
}
const drag = shallowRef<Drag | null>(null);
let observer: ResizeObserver | null = null;
let suppressedClick = false;
let request = 0;
const threads = computed(() => {
  const entries = new Map(state.pins.map((thread) => [thread.id, thread]));
  if (state.thread) entries.set(state.thread.id, state.thread);
  return [...entries.values()];
});
function position(thread: CommentThread | null): CommentPosition {
  const id = thread?.id ?? null;
  if (drag.value && (drag.value.thread?.id ?? null) === id) return drag.value.position;
  if (optimistic.value?.id === id) return optimistic.value.position;
  if (!thread) return state.draftPosition ?? { x: 0, y: 0 };
  if (thread.position) return thread.position;
  // Discussions created before spatial placement appear next to their source.
  const source =
    thread.source.type === "ideation_idea"
      ? notes.find((note) => note.id === thread.source.id)
      : groups.find((group) => group.id === thread.source.id);
  const canvas = source?.canvas;
  const index = Math.max(
    0,
    threads.value.findIndex((item) => item.id === id),
  );
  return {
    x: (canvas?.x ?? 0) + 32 + (index % 5) * 40,
    y: (canvas?.y ?? 0) + 32 + Math.floor(index / 5) * 40,
  };
}
function screen(point: CommentPosition) {
  return { x: view.x + point.x * view.zoom, y: view.y + point.y * view.zoom };
}
const pins = computed(() =>
  threads.value.map((thread) => ({ thread, point: screen(position(thread)) })),
);
const activePoint = computed(() => screen(position(state.thread)));
const hovered = computed(() => pins.value.find((pin) => pin.thread.id === hoverId.value));
const popupPosition = computed(() =>
  commentPopoverPosition(activePoint.value, view, popupSize.value),
);
function push(
  event: string,
  payload = {},
  callback?: (reply: { [key: string]: unknown }) => void,
  onError?: () => void,
) {
  live.pushEvent(
    event,
    { ...payload, epoch, session_id: sessionId, comment_context: state.context },
    callback,
    onError,
  );
}
function select(thread: CommentThread, event: MouseEvent) {
  if (suppressedClick && event.detail !== 0) {
    suppressedClick = false;
    return;
  }
  suppressedClick = false;
  hoverId.value = null;
  push("comments_select_thread", { thread_id: thread.id });
}
function start(event: PointerEvent, thread: CommentThread | null) {
  if (event.button !== 0 || !state.canComment || pending.value) return;
  event.preventDefault();
  const target = event.currentTarget as HTMLElement;
  const origin = position(thread);
  drag.value = {
    thread,
    target,
    pointerId: event.pointerId,
    start: { x: event.clientX, y: event.clientY },
    origin,
    position: origin,
    moved: false,
  };
  target.focus({ preventScroll: true });
  target.setPointerCapture?.(event.pointerId);
  moveError.value = false;
}
function move(event: PointerEvent) {
  const current = drag.value;
  if (!current || current.pointerId !== event.pointerId) return;
  const dx = event.clientX - current.start.x,
    dy = event.clientY - current.start.y;
  if (!current.moved && Math.hypot(dx, dy) < 4) return;
  event.preventDefault();
  hoverId.value = null;
  drag.value = {
    ...current,
    moved: true,
    position: { x: current.origin.x + dx / view.zoom, y: current.origin.y + dy / view.zoom },
  };
}
function end() {
  const current = drag.value;
  drag.value = null;
  if (current?.pointerId != null && current.target.hasPointerCapture?.(current.pointerId))
    current.target.releasePointerCapture(current.pointerId);
  return current;
}
function cancel() {
  if (drag.value?.moved) suppressedClick = true;
  end();
}
function commit() {
  const current = end();
  if (!current?.moved) return;
  suppressedClick = current.pointerId !== null;
  const token = ++request;
  pending.value = true;
  optimistic.value = { id: current.thread?.id ?? null, position: current.position };
  const finish = (failed: boolean) => {
    if (token !== request) return;
    pending.value = false;
    optimistic.value = null;
    moveError.value = failed;
  };
  push(
    current.thread ? "comments_move" : "comments_place",
    {
      position: current.position,
      ...(current.thread
        ? { thread_id: current.thread.id, expected_revision: current.thread.revision }
        : {}),
    },
    (reply) => finish(reply.ok !== true),
    () => finish(true),
  );
}
function release(event: PointerEvent) {
  if (drag.value?.pointerId !== event.pointerId) return;
  move(event);
  commit();
}
function key(event: KeyboardEvent, thread: CommentThread | null) {
  if (event.key === "Escape") {
    event.preventDefault();
    cancel();
    return;
  }
  if (event.key === "Enter" && drag.value) {
    event.preventDefault();
    commit();
    return;
  }
  const directions: { [key: string]: CommentPosition } = {
    ArrowLeft: { x: -1, y: 0 },
    ArrowRight: { x: 1, y: 0 },
    ArrowUp: { x: 0, y: -1 },
    ArrowDown: { x: 0, y: 1 },
  };
  const direction = directions[event.key];
  if (!direction || !state.canComment || pending.value || event.metaKey || event.ctrlKey) return;
  event.preventDefault();
  const point = position(thread);
  const current = drag.value ?? {
    thread,
    target: event.currentTarget as HTMLElement,
    pointerId: null,
    start: point,
    origin: point,
    position: point,
    moved: false,
  };
  const step = (event.shiftKey ? 1 : 10) / view.zoom;
  drag.value = {
    ...current,
    moved: true,
    position: {
      x: current.position.x + direction.x * step,
      y: current.position.y + direction.y * step,
    },
  };
}
watch(
  () => `${epoch}:${sessionId}:${state.context}`,
  () => {
    cancel();
    request++;
    pending.value = false;
    optimistic.value = null;
    hoverId.value = null;
    moveError.value = false;
  },
);
watch(
  () => state.pins.map((thread) => `${thread.id}:${thread.revision}`).join(","),
  () => {
    const current = drag.value?.thread;
    if (
      current &&
      !state.pins.some((thread) => thread.id === current.id && thread.revision === current.revision)
    )
      cancel();
  },
);
watch(
  () => [state.open, state.thread?.id, state.context],
  async () => {
    if (!state.open) return;
    await nextTick();
    const point = activePoint.value;
    if (point.x < 24 || point.y < 24 || point.x > view.width - 24 || point.y > view.height - 24)
      emit("focus", position(state.thread));
  },
  { immediate: true },
);
watch(popup, (element) => {
  observer?.disconnect();
  if (!element) return;
  const measure = () => {
    popupSize.value = { width: element.offsetWidth, height: element.offsetHeight };
  };
  observer = new ResizeObserver(measure);
  observer.observe(element);
  measure();
});
onUnmounted(() => {
  observer?.disconnect();
  cancel();
});
</script>

<template>
  <div
    data-testid="brainstorming-canvas-comments"
    data-canvas-chrome
    class="pointer-events-none absolute inset-0 z-20 overflow-hidden"
    @keydown.stop
    @wheel.stop
    @dblclick.stop
  >
    <button
      v-for="pin in pins"
      :id="`brainstorming-comment-pin-${pin.thread.id}`"
      :key="pin.thread.id"
      type="button"
      class="pointer-events-auto absolute flex size-8 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border-2 border-background bg-primary text-primary-foreground shadow-md transition-shadow hover:shadow-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      :style="{ left: `${pin.point.x}px`, top: `${pin.point.y}px` }"
      :aria-label="
        $t('brainstormingComments.pin_label', { author: pin.thread.author.display_name })
      "
      :aria-expanded="state.open && state.thread?.id === pin.thread.id"
      :aria-busy="pending && optimistic?.id === pin.thread.id"
      aria-describedby="brainstorming-comment-move-help"
      @click.stop="select(pin.thread, $event)"
      @pointerdown.stop="start($event, pin.thread)"
      @pointermove.stop="move"
      @pointerup.stop="release"
      @pointercancel.stop="cancel"
      @lostpointercapture.stop="cancel"
      @keydown="key($event, pin.thread)"
      @blur="drag?.pointerId === null && cancel()"
      @pointerenter="hoverId = pin.thread.id"
      @pointerleave="hoverId = null"
    >
      <MessageCircle class="size-4" />
    </button>
    <button
      v-if="state.open && !state.thread"
      id="brainstorming-comment-draft-pin"
      type="button"
      class="pointer-events-auto absolute flex size-8 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border-2 border-dashed border-primary bg-background text-primary shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      :style="{ left: `${activePoint.x}px`, top: `${activePoint.y}px` }"
      :aria-label="$t('brainstormingComments.new_thread')"
      :aria-busy="pending"
      aria-describedby="brainstorming-comment-move-help"
      @pointerdown.stop="start($event, null)"
      @pointermove.stop="move"
      @pointerup.stop="release"
      @pointercancel.stop="cancel"
      @lostpointercapture.stop="cancel"
      @keydown="key($event, null)"
      @blur="drag?.pointerId === null && cancel()"
    >
      <Plus class="size-4" />
    </button>
    <p id="brainstorming-comment-move-help" class="sr-only">
      {{ $t("brainstormingComments.keyboard_move_hint") }}
    </p>
    <div
      v-if="hovered && !state.open && !drag"
      id="brainstorming-comment-preview"
      class="absolute max-w-64 rounded-lg border border-border bg-popover p-3 text-xs text-popover-foreground shadow-lg"
      :style="{
        left: `${commentPopoverPosition(hovered.point, view, { width: 256, height: 100 }).x}px`,
        top: `${commentPopoverPosition(hovered.point, view, { width: 256, height: 100 }).y}px`,
      }"
    >
      <p class="font-medium">{{ hovered.thread.author.display_name }}</p>
      <p class="mt-1 line-clamp-3">{{ hovered.thread.preview }}</p>
    </div>
    <div
      v-if="state.open"
      id="brainstorming-comment-popover"
      ref="popup"
      class="pointer-events-auto absolute flex flex-col"
      :style="{
        left: `${popupPosition.x}px`,
        top: `${popupPosition.y}px`,
        width: `${Math.min(360, Math.max(0, view.width - 24))}px`,
        maxHeight: `${Math.max(0, view.height - 24)}px`,
      }"
      @pointerdown.stop
      @keydown.esc.stop="push('comments_close')"
    >
      <BrainstormingCommentPopover
        :state="state"
        :epoch="epoch"
        :session-id="sessionId"
        :base-url="baseUrl"
      />
    </div>
    <p
      v-if="moveError"
      role="alert"
      class="absolute bottom-20 left-1/2 -translate-x-1/2 rounded-lg bg-destructive px-3 py-2 text-sm text-destructive-foreground"
    >
      {{ $t("brainstormingComments.update_failed") }}
    </p>
  </div>
</template>
