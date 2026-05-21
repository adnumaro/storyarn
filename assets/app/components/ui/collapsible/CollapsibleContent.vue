<script setup lang="ts">
import type { Component } from "vue";
import { CollapsibleContent, type AsTag } from "reka-ui";

const props = defineProps<{
  forceMount?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
}>();
</script>

<template>
  <CollapsibleContent data-slot="collapsible-content" v-bind="props">
    <slot />
  </CollapsibleContent>
</template>
