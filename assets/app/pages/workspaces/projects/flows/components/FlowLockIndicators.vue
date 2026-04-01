<script setup>
import { Lock } from "lucide-vue-next";
import { computed } from "vue";

const { locks, nodePositions, currentUserId } = defineProps({
  locks: { type: Object, default: () => ({}) },
  nodePositions: { type: Object, default: () => ({}) },
  currentUserId: { type: [Number, String], default: 0 },
});

const otherUserLocks = computed(() => {
  const result = [];
  for (const [nodeId, lock] of Object.entries(locks)) {
    if (lock.user_id !== currentUserId && nodePositions[nodeId]) {
      result.push({
        nodeId,
        ...lock,
        ...nodePositions[nodeId],
      });
    }
  }
  return result;
});

function emailName(email) {
  return email?.split("@")[0] || "User";
}
</script>

<template>
  <div
    v-for="lock in otherUserLocks"
    :key="lock.nodeId"
    class="absolute pointer-events-none"
    :style="{
      left: `${lock.x + lock.width - 8}px`,
      top: `${lock.y - 8}px`,
    }"
  >
    <div
      class="flex items-center gap-1 px-1.5 py-0.5 rounded-full text-[10px] border shadow-sm pointer-events-auto"
      :style="{
        color: lock.user_color,
        borderColor: lock.user_color,
        backgroundColor: 'hsl(var(--background))',
      }"
    >
      <Lock class="size-3" />
      <span>{{ emailName(lock.user_email) }}</span>
    </div>
  </div>
</template>
