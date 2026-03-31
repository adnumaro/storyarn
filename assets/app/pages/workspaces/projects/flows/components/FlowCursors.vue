<script setup>
import { MousePointer2 } from "lucide-vue-next";
import { onMounted, onUnmounted, reactive, ref } from "vue";
import { useLive } from "@composables/useLive.js";

const props = defineProps({
  areaTransform: { type: Object, default: () => ({ x: 0, y: 0, k: 1 }) },
  currentUserId: { type: [Number, String], default: 0 },
  containerEl: { type: Object, default: null },
});

const live = useLive();
const cursors = reactive(new Map());
let lastSend = 0;
const THROTTLE_MS = 50;
const FADE_MS = 3000;
let fadeTimers = new Map();

function emailName(email) {
  return email?.split("@")[0] || "User";
}

// Broadcast local cursor
function onMouseMove(e) {
  const now = Date.now();
  if (now - lastSend < THROTTLE_MS) return;
  lastSend = now;

  const el = props.containerEl;
  if (!el) return;
  const rect = el.getBoundingClientRect();
  const x = e.clientX - rect.left;
  const y = e.clientY - rect.top;

  const t = props.areaTransform;
  const canvasX = (x - t.x) / t.k;
  const canvasY = (y - t.y) / t.k;

  live.pushEvent("cursor_moved", { x: canvasX, y: canvasY });
}

// Receive remote cursor
live.handleEvent("cursor_update", (data) => {
  if (String(data.user_id) === String(props.currentUserId)) return;

  const t = props.areaTransform;
  const screenX = data.x * t.k + t.x;
  const screenY = data.y * t.k + t.y;

  cursors.set(data.user_id, {
    x: screenX,
    y: screenY,
    email: data.user_email,
    color: data.user_color || "#888",
    opacity: 1,
  });

  // Fade after inactivity
  if (fadeTimers.has(data.user_id)) clearTimeout(fadeTimers.get(data.user_id));
  fadeTimers.set(
    data.user_id,
    setTimeout(() => {
      const c = cursors.get(data.user_id);
      if (c) {
        c.opacity = 0.3;
        cursors.set(data.user_id, { ...c });
      }
    }, FADE_MS),
  );
});

live.handleEvent("cursor_leave", (data) => {
  cursors.delete(data.user_id);
  if (fadeTimers.has(data.user_id)) {
    clearTimeout(fadeTimers.get(data.user_id));
    fadeTimers.delete(data.user_id);
  }
});

onMounted(() => {
  props.containerEl?.addEventListener("mousemove", onMouseMove);
});

onUnmounted(() => {
  props.containerEl?.removeEventListener("mousemove", onMouseMove);
  for (const timer of fadeTimers.values()) clearTimeout(timer);
});
</script>

<template>
  <div class="absolute inset-0 pointer-events-none z-[100]">
    <div
      v-for="[userId, cursor] in cursors"
      :key="userId"
      class="absolute top-0 left-0"
      :style="{
        transform: `translate(${cursor.x}px, ${cursor.y}px)`,
        opacity: cursor.opacity,
        transition: 'transform 0.05s linear, opacity 0.3s ease',
      }"
    >
      <MousePointer2
        class="size-5"
        :style="{ color: cursor.color, filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.3))' }"
      />
      <span
        class="absolute top-5 left-3 text-[10px] text-white px-1.5 py-0.5 rounded whitespace-nowrap"
        :style="{ backgroundColor: cursor.color }"
      >
        {{ emailName(cursor.email) }}
      </span>
    </div>
  </div>
</template>
