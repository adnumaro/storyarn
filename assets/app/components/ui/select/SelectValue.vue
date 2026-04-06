<script setup lang="ts">
import type { Component } from "vue";
import { SelectValue, type AsTag } from "reka-ui";

const props = defineProps<{
  placeholder?: string;
  asChild?: boolean;
  as?: AsTag | Component;
}>();
</script>

<template>
  <SelectValue data-slot="select-value" v-bind="props">
    <slot />
  </SelectValue>
</template>
