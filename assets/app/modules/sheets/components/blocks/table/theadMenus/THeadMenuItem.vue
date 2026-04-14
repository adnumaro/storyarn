<script setup lang="ts">
import type { AsTag } from "reka-ui";
import type { Component, HTMLAttributes } from "vue";
import { cn } from "@utils/utils.ts";

const { as = "button", class: className } = defineProps<{
  as?: AsTag | Component;
  class?: HTMLAttributes["class"];
}>();
</script>

<template>
  <div class="p-1">
    <component
      :is="as"
      :class="
        cn(
          'flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent',
          className,
        )
      "
    >
      <slot />
    </component>
  </div>
</template>
