<script setup lang="ts">
import type { Component } from "vue";
import { SelectItemText, type AsTag } from "reka-ui";

const props = defineProps<{
  asChild?: boolean;
  as?: AsTag | Component;
}>();
</script>

<template>
  <SelectItemText data-slot="select-item-text" v-bind="props">
    <slot />
  </SelectItemText>
</template>
