<script setup lang="ts">
import type { Component } from "vue";
import { PopoverAnchor, type AsTag } from "reka-ui";

const props = defineProps<{
  reference?: HTMLElement;
  asChild?: boolean;
  as?: AsTag | Component;
}>();
</script>

<template>
  <PopoverAnchor data-slot="popover-anchor" v-bind="props">
    <slot />
  </PopoverAnchor>
</template>
