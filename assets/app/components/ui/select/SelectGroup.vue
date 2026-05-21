<script setup lang="ts">
import type { Component } from "vue";
import { SelectGroup, type AsTag } from "reka-ui";

const props = defineProps<{
  asChild?: boolean;
  as?: AsTag | Component;
}>();
</script>

<template>
  <SelectGroup data-slot="select-group" v-bind="props">
    <slot />
  </SelectGroup>
</template>
