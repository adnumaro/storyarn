<script setup lang="ts">
import { onMounted, onUnmounted, reactive, watch } from "vue";
import { MousePointer2 } from "@lucide/vue";
import { useLive } from "@shared/composables/useLive";
import type { BoardContext } from "../types";
interface Cursor {
  x: number;
  y: number;
  name: string;
  color: string;
  seen: number;
}
const { container, view, context } = defineProps<{
  container: HTMLElement | null;
  view: { x: number; y: number; zoom: number };
  context: BoardContext;
}>();
const live = useLive();
const cursors = reactive(new Map<number, Cursor>());
let last = 0,
  eventId: number | undefined,
  timer: ReturnType<typeof setInterval> | undefined;
function move(event: PointerEvent) {
  if (
    Date.now() - last < 100 ||
    !container ||
    (event.target as HTMLElement).closest("[data-canvas-chrome]")
  )
    return;
  last = Date.now();
  const rect = container.getBoundingClientRect();
  live.pushEvent("canvas_cursor", {
    ...context,
    x: (event.clientX - rect.left - view.x) / view.zoom,
    y: (event.clientY - rect.top - view.y) / view.zoom,
  });
}
watch(
  () => container,
  (next, old) => {
    old?.removeEventListener("pointermove", move);
    next?.addEventListener("pointermove", move);
  },
  { immediate: true },
);
watch(
  () => `${context.epoch}:${context.session_id}`,
  () => cursors.clear(),
);
onMounted(() => {
  eventId = live.handleEvent("canvas_cursor", (data) => {
    if (
      data.epoch !== context.epoch ||
      data.session_id !== context.session_id ||
      typeof data.user_id !== "number" ||
      typeof data.x !== "number" ||
      typeof data.y !== "number" ||
      typeof data.name !== "string" ||
      typeof data.color !== "string"
    )
      return;
    cursors.set(data.user_id, {
      x: data.x,
      y: data.y,
      name: data.name,
      color: data.color,
      seen: Date.now(),
    });
  });
  timer = setInterval(() => {
    for (const [id, cursor] of cursors) if (Date.now() - cursor.seen > 5000) cursors.delete(id);
  }, 1000);
});
onUnmounted(() => {
  container?.removeEventListener("pointermove", move);
  if (eventId !== undefined) live.removeHandleEvent(eventId);
  clearInterval(timer);
});
</script>
<template>
  <div class="pointer-events-none absolute inset-0 z-20 overflow-hidden" aria-hidden="true">
    <div
      v-for="[id, cursor] in cursors"
      :key="id"
      class="absolute left-0 top-0 transition-transform duration-100 ease-linear"
      :style="{
        transform: `translate(${view.x + cursor.x * view.zoom}px, ${view.y + cursor.y * view.zoom}px)`,
        color: cursor.color,
      }"
    >
      <MousePointer2 class="size-5 fill-current stroke-background" /><span
        class="ml-4 block max-w-40 truncate rounded px-2 py-1 text-[11px] text-white"
        :style="{ backgroundColor: cursor.color }"
        >{{ cursor.name }}</span
      >
    </div>
  </div>
</template>
