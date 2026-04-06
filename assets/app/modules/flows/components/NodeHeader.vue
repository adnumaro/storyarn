<script setup>
import { computed } from "vue";
import { headerStyle } from "../lib/render-helpers.js";

const { color, icon, label, avatarUrl } = defineProps({
  color: { type: String, default: "#3b82f6" },
  icon: { type: [Object, Function, null], default: null },
  label: { type: String, default: "" },
  avatarUrl: { type: String, default: null },
});

const bgStyle = computed(() => headerStyle(color));
</script>

<template>
  <div
    class="header px-3 py-2 rounded-t-[10px] flex items-center gap-2 text-white font-medium text-[13px]"
    :style="bgStyle"
  >
    <img
      v-if="avatarUrl"
      :src="avatarUrl"
      alt=""
      class="size-8 rounded-full object-cover shrink-0"
    />
    <component v-else-if="icon" :is="icon" class="size-4 shrink-0" />
    <span class="overflow-hidden text-ellipsis whitespace-nowrap">{{ label }}</span>
    <slot />
  </div>
</template>
