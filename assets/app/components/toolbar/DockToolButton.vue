<script setup lang="ts">
import type { Component } from "vue";

const {
  icon,
  active = false,
  tooltipTitle,
  tooltipDescription = "",
  tag = "button",
  href = null,
} = defineProps<{
  icon: Component;
  active?: boolean;
  tooltipTitle: string;
  tooltipDescription?: string;
  tag?: string;
  href?: string | null;
}>();

const emit = defineEmits<{
  click: [];
}>();
</script>

<template>
  <div class="dock-item group relative">
    <component
      :is="tag"
      :type="tag === 'button' ? 'button' : undefined"
      :href="href"
      :data-phx-link="tag === 'a' ? 'redirect' : undefined"
      :data-phx-link-state="tag === 'a' ? 'push' : undefined"
      class="dock-btn"
      :class="{ 'dock-btn-active': active }"
      :aria-label="tooltipTitle"
      :title="tooltipTitle"
      @click="emit('click')"
    >
      <component :is="icon" class="size-5" />
    </component>
    <div class="dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">{{ tooltipTitle }}</div>
      <div v-if="tooltipDescription" class="text-xs text-muted-foreground leading-relaxed">
        {{ tooltipDescription }}
      </div>
    </div>
  </div>
</template>
