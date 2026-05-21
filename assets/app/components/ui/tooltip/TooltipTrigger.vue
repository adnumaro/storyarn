<script setup lang="ts">
import type { Component } from "vue";
import { TooltipTrigger, type AsTag } from "reka-ui";

const props = defineProps<{
  reference?: HTMLElement;
  asChild?: boolean;
  as?: AsTag | Component;
}>();
</script>

<template>
  <TooltipTrigger data-slot="tooltip-trigger" v-bind="props">
    <slot />
  </TooltipTrigger>
</template>
