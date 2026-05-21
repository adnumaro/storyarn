<script setup lang="ts">
import type { Component } from "vue";
import { CollapsibleTrigger, type AsTag } from "reka-ui";

const props = defineProps<{
  asChild?: boolean;
  as?: AsTag | Component;
}>();
</script>

<template>
  <CollapsibleTrigger data-slot="collapsible-trigger" v-bind="props">
    <slot />
  </CollapsibleTrigger>
</template>
