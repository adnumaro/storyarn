<script setup lang="ts">
import type { Component } from "vue";
import { computed } from "vue";
import { headerStyle } from "../../../lib/render-helpers";

const {
  color = "#3b82f6",
  icon = null,
  label = "",
  avatarUrl = null,
} = defineProps<{
  color?: string;
  icon?: Component | null;
  label?: string;
  avatarUrl?: string | null;
}>();

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
